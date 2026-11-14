/**
 * TetherPass Ultrasonic Audio Handshake Receiver
 * Captures high-frequency acoustic FSK chirps (18 kHz - 19.5 kHz) via Web Audio API
 * to authenticate desktop sessions air-gapped without camera or cloud.
 */

class UltrasonicHandshakeListener {
  constructor(onTokenReceived, onStatusChange) {
    this.onTokenReceived = onTokenReceived;
    this.onStatusChange = onStatusChange || (() => {});
    this.audioContext = null;
    this.mediaStream = null;
    this.analyser = null;
    this.isListening = false;
    this.animFrameId = null;

    // Frequencies matching the mobile transmitter
    this.FREQ_SYNC = 19400; // Preamble
    this.FREQ_ZERO = 18200; // Bit 0
    this.FREQ_ONE  = 18800; // Bit 1

    this.BIT_DURATION_MS = 40;
    this.state = 'IDLE'; // 'IDLE', 'SYNC_DETECTED', 'READING'
    this.syncStartTime = 0;
    this.bitStartTime = 0;
    this.receivedBits = [];
    this.expectedBits = 0;
  }

  async startListening() {
    if (this.isListening) return true;

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
        }
      });
      this.mediaStream = stream;

      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      this.audioContext = new AudioCtx();
      const source = this.audioContext.createMediaStreamSource(stream);

      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = 2048;
      this.analyser.smoothingTimeConstant = 0.1;
      source.connect(this.analyser);

      this.isListening = true;
      this.state = 'IDLE';
      this.onStatusChange({ status: 'LISTENING', message: 'Listening for ultrasonic acoustic chirp (~18.5 kHz)...' });
      this._processAudioLoop();
      return true;
    } catch (err) {
      console.warn('[Ultrasonic] Microphone access error:', err);
      this.onStatusChange({ status: 'ERROR', message: 'Microphone permission required for sound handshake.' });
      return false;
    }
  }

  stopListening() {
    this.isListening = false;
    if (this.animFrameId) {
      cancelAnimationFrame(this.animFrameId);
      this.animFrameId = null;
    }
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach(track => track.stop());
      this.mediaStream = null;
    }
    if (this.audioContext && this.audioContext.state !== 'closed') {
      this.audioContext.close().catch(() => {});
      this.audioContext = null;
    }
    this.state = 'IDLE';
    this.onStatusChange({ status: 'STOPPED', message: 'Listener stopped.' });
  }

  _getBin(freq) {
    const sampleRate = this.audioContext.sampleRate;
    return Math.round(freq / (sampleRate / this.analyser.fftSize));
  }

  _getBandPower(dataArray, binCenter, span = 2) {
    let sum = 0;
    for (let b = binCenter - span; b <= binCenter + span; b++) {
      if (b >= 0 && b < dataArray.length) {
        sum += dataArray[b];
      }
    }
    return sum / (span * 2 + 1);
  }

  _processAudioLoop() {
    if (!this.isListening) return;

    const bufferLength = this.analyser.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    this.analyser.getByteFrequencyData(dataArray);

    const binSync = this._getBin(this.FREQ_SYNC);
    const binZero = this._getBin(this.FREQ_ZERO);
    const binOne  = this._getBin(this.FREQ_ONE);

    const powerSync = this._getBandPower(dataArray, binSync);
    const powerZero = this._getBandPower(dataArray, binZero);
    const powerOne  = this._getBandPower(dataArray, binOne);

    // Baseline noise floor estimate in adjacent quiet band (17.5 kHz)
    const binNoise = this._getBin(17500);
    const powerNoise = Math.max(15, this._getBandPower(dataArray, binNoise) * 1.5);

    const now = performance.now();

    switch (this.state) {
      case 'IDLE':
        // Look for sharp spike at 19.4 kHz (Sync preamble)
        if (powerSync > 70 && powerSync > powerNoise && powerSync > (powerZero + 30) && powerSync > (powerOne + 30)) {
          this.state = 'SYNC_DETECTED';
          this.syncStartTime = now;
          this.onStatusChange({ status: 'SYNCING', message: '🔊 Acoustic handshake detected! Decoding...' });
        }
        break;

      case 'SYNC_DETECTED':
        // Wait for sync burst to pass (~160ms) and transition to data reading
        if (now - this.syncStartTime > 160) {
          this.state = 'READING';
          this.bitStartTime = now;
          this.receivedBits = [];
          this.sampleTimer = null;
          this._startBitClock();
        }
        break;

      case 'READING':
        // Handled via sample interval clock (_startBitClock)
        break;
    }

    this.animFrameId = requestAnimationFrame(() => this._processAudioLoop());
  }

  _startBitClock() {
    // Read bits periodically according to bit duration (40ms)
    // Expect 4 characters (32 bits) + 8-bit checksum = 40 bits total
    const totalExpectedBits = 40;
    const intervalMs = this.BIT_DURATION_MS;

    const intervalId = setInterval(() => {
      if (!this.isListening || this.state !== 'READING') {
        clearInterval(intervalId);
        return;
      }

      const bufferLength = this.analyser.frequencyBinCount;
      const dataArray = new Uint8Array(bufferLength);
      this.analyser.getByteFrequencyData(dataArray);

      const binZero = this._getBin(this.FREQ_ZERO);
      const binOne  = this._getBin(this.FREQ_ONE);

      const powerZero = this._getBandPower(dataArray, binZero);
      const powerOne  = this._getBandPower(dataArray, binOne);

      const bit = powerOne >= powerZero ? 1 : 0;
      this.receivedBits.push(bit);

      if (this.receivedBits.length >= totalExpectedBits) {
        clearInterval(intervalId);
        this._decodeAndVerifyPacket();
      }
    }, intervalMs);
  }

  _decodeAndVerifyPacket() {
    const bits = this.receivedBits;
    if (bits.length < 16) {
      this.state = 'IDLE';
      this.onStatusChange({ status: 'LISTENING', message: 'Acoustic signal too short. Ready...' });
      return;
    }

    // Convert bits to bytes
    const bytes = [];
    for (let i = 0; i + 8 <= bits.length; i += 8) {
      let b = 0;
      for (let j = 0; j < 8; j++) {
        b = (b << 1) | bits[i + j];
      }
      bytes.push(b);
    }

    if (bytes.length < 2) {
      this.state = 'IDLE';
      return;
    }

    const receivedChecksum = bytes.pop();
    var calculatedChecksum = 0x5A;
    for (const b of bytes) {
      calculatedChecksum = (calculatedChecksum ^ b) & 0xFF;
    }

    let decodedString = '';
    for (const b of bytes) {
      decodedString += String.fromCharCode(b);
    }

    if (calculatedChecksum === receivedChecksum && decodedString.length > 0) {
      console.log('[Ultrasonic] Handshake Verified! Token:', decodedString);
      this.onStatusChange({ status: 'SUCCESS', message: `✓ Handshake verified: [${decodedString}]` });
      this.onTokenReceived(decodedString);
    } else {
      console.warn('[Ultrasonic] Checksum mismatch. Retrying...');
      this.onStatusChange({ status: 'LISTENING', message: 'Audio checksum mismatch. Retrying...' });
    }

    this.state = 'IDLE';
  }
}
