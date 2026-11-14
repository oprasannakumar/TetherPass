package com.example.card_vault

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * UltrasonicTransmitter
 * Generates near-inaudible high-frequency acoustic chirps (18 kHz - 19.5 kHz)
 * using Frequency Shift Keying (FSK) to tether and unlock the desktop browser extension.
 */
object UltrasonicTransmitter {
    private const val SAMPLE_RATE = 44100
    private const val FREQ_SYNC = 19400.0   // 19.4 kHz preamble sync
    private const val FREQ_ZERO = 18200.0   // 18.2 kHz bit 0
    private const val FREQ_ONE  = 18800.0   // 18.8 kHz bit 1

    private const val DURATION_SYNC_MS = 160
    private const val DURATION_BIT_MS  = 40

    @Volatile
    private var isPlaying = false

    fun playToken(token: String, onComplete: (() -> Unit)? = null) {
        if (isPlaying) return
        isPlaying = true

        thread(name = "TetherPass-Ultrasonic") {
            var audioTrack: AudioTrack? = null
            try {
                val cleanToken = token.trim().uppercase()
                val bytes = cleanToken.toByteArray(Charsets.UTF_8)
                if (bytes.isEmpty()) {
                    isPlaying = false
                    return@thread
                }

                // Calculate simple 8-bit checksum to eliminate false positives
                var checksum = 0x5A
                for (b in bytes) {
                    checksum = (checksum xor b.toInt()) and 0xFF
                }

                val bitList = ArrayList<Int>()
                for (b in bytes) {
                    for (i in 7 downTo 0) {
                        bitList.add((b.toInt() shr i) and 1)
                    }
                }
                for (i in 7 downTo 0) {
                    bitList.add((checksum shr i) and 1)
                }

                val syncSamples = (SAMPLE_RATE * (DURATION_SYNC_MS / 1000.0)).toInt()
                val bitSamples  = (SAMPLE_RATE * (DURATION_BIT_MS / 1000.0)).toInt()
                val pauseSamples = (SAMPLE_RATE * 0.05).toInt()
                val totalSamples = syncSamples + (bitList.size * bitSamples) + pauseSamples

                val pcmData = ShortArray(totalSamples)
                var offset = 0
                var phase = 0.0

                // 1. Synthesize Sync Preamble (19.4 kHz) with Hann window envelope to prevent audible clicks
                val syncStep = 2.0 * PI * FREQ_SYNC / SAMPLE_RATE
                for (i in 0 until syncSamples) {
                    val envelope = 0.5 * (1.0 - cos(2.0 * PI * i / syncSamples))
                    val sample = (sin(phase) * 32767.0 * 0.9 * envelope).toInt().toShort()
                    pcmData[offset++] = sample
                    phase += syncStep
                    if (phase >= 2.0 * PI) phase -= 2.0 * PI
                }

                // 2. Synthesize Data Bits (18.2 kHz for 0, 18.8 kHz for 1) with continuous phase
                for (bit in bitList) {
                    val freq = if (bit == 1) FREQ_ONE else FREQ_ZERO
                    val step = 2.0 * PI * freq / SAMPLE_RATE
                    for (i in 0 until bitSamples) {
                        val envelope = 0.5 * (1.0 - cos(2.0 * PI * i / bitSamples))
                        val sample = (sin(phase) * 32767.0 * 0.9 * envelope).toInt().toShort()
                        pcmData[offset++] = sample
                        phase += step
                        if (phase >= 2.0 * PI) phase -= 2.0 * PI
                    }
                }

                val minBuf = AudioTrack.getMinBufferSize(
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )

                audioTrack = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(max(minBuf, pcmData.size * 2))
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                audioTrack.write(pcmData, 0, pcmData.size)
                audioTrack.play()

                // Wait for playback to finish
                val playDurationMs = (totalSamples * 1000L / SAMPLE_RATE) + 100
                Thread.sleep(playDurationMs)

                audioTrack.stop()
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                try {
                    audioTrack?.release()
                } catch (ignored: Exception) {}
                isPlaying = false
                onComplete?.invoke()
            }
        }
    }
}
