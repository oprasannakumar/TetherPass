import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/vault_item.dart';

/// Detects the card network, issuing bank, card tier, and type from a card number,
/// utilizing a comprehensive offline Bank Identification Number (BIN/IIN) database
/// and validating the number using the Luhn algorithm.
class CardDetector {
  CardDetector._();

  // ─── Luhn Validation ───────────────────────────────────────────────────────

  /// Returns [true] if [number] passes the Luhn check.
  static bool luhnCheck(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;

    int sum = 0;
    bool alternate = false;

    for (int i = digits.length - 1; i >= 0; i--) {
      int n = int.parse(digits[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }

    return sum % 10 == 0;
  }

  static bool isValidLuhn(String number) => luhnCheck(number);

  // ─── Network Detection (Card Scheme / Brand) ───────────────────────────────

  /// Returns the card network name derived from [number].
  ///
  /// Supports: RuPay, Visa, Mastercard, Amex, Discover, Diners, JCB, UnionPay, Maestro.
  static String detectNetwork(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return 'Unknown';

    final n2 = int.tryParse(d.length >= 2 ? d.substring(0, 2) : d.padRight(2, '0')) ?? 0;
    final n3 = int.tryParse(d.length >= 3 ? d.substring(0, 3) : d.padRight(3, '0')) ?? 0;
    final n4 = int.tryParse(d.length >= 4 ? d.substring(0, 4) : d.padRight(4, '0')) ?? 0;
    final n6 = int.tryParse(d.length >= 6 ? d.substring(0, 6) : d.padRight(6, '0')) ?? 0;

    // 1. RuPay: Checked first to prioritize domestic ranges before global partners
    if (d.startsWith('60') && !d.startsWith('6011')) return 'RuPay';
    if (d.startsWith('6521') || d.startsWith('6522') || d.startsWith('6528') || d.startsWith('6530') || d.startsWith('6531')) return 'RuPay';
    if (d.startsWith('508')) return 'RuPay';
    if (n2 == 81 || n2 == 82) return 'RuPay';
    if (d.startsWith('3538') || d.startsWith('3561')) return 'RuPay';

    // 2. Visa: starts with 4
    if (d.startsWith('4')) return 'Visa';

    // 3. Mastercard: 51-55 or 2221-2720
    if (n2 >= 51 && n2 <= 55) return 'Mastercard';
    if (n4 >= 2221 && n4 <= 2720) return 'Mastercard';

    // 4. American Express: starts with 34 or 37
    if (n2 == 34 || n2 == 37) return 'Amex';

    // 5. Discover: 6011, 622126-622925, 644-649, 65 (non-RuPay)
    if (d.startsWith('6011')) return 'Discover';
    if (n6 >= 622126 && n6 <= 622925) return 'Discover';
    if (n3 >= 644 && n3 <= 649) return 'Discover';
    if (n2 == 65) return 'Discover';

    // 6. Diners Club: 300-305, 3095, 36, 38, 39
    if (n2 == 36 || n2 == 38 || n2 == 39) return 'Diners';
    if (n3 >= 300 && n3 <= 305) return 'Diners';
    if (d.startsWith('3095')) return 'Diners';

    // 7. JCB: 3528-3589
    if (n4 >= 3528 && n4 <= 3589) return 'JCB';

    // 8. UnionPay: starts with 62
    if (n2 == 62) return 'UnionPay';

    // 9. Maestro: 50 (non-508), 56-58, 67
    if (d.startsWith('50') && !d.startsWith('508')) return 'Maestro';
    if (n2 >= 56 && n2 <= 58) return 'Maestro';
    if (n2 == 67) return 'Maestro';

    return 'Unknown';
  }

  // ─── Comprehensive Bank Identification Number (BIN / IIN) Database ─────────

  static const Map<String, String> _binBankMap = {
    // ── State Bank of India (SBI & SBI Cards) ──
    '400669': 'SBI', '417633': 'SBI', '440403': 'SBI', '524606': 'SBI', '534384': 'SBI',
    '510223': 'SBI', '433587': 'SBI', '405450': 'SBI', '222495': 'SBI', '406584': 'SBI',
    '459150': 'SBI', '472642': 'SBI', '607075': 'SBI', '607076': 'SBI', '607077': 'SBI',
    '607078': 'SBI', '607079': 'SBI', '652150': 'SBI', '652151': 'SBI', '652152': 'SBI',
    '508535': 'SBI', '508505': 'SBI', '421315': 'SBI', '421316': 'SBI', '421317': 'SBI',
    '472643': 'SBI', '622018': 'SBI', '607214': 'SBI', '607213': 'SBI', '607216': 'SBI',
    '607217': 'SBI', '459151': 'SBI', '459152': 'SBI', '531338': 'SBI', '517855': 'SBI',
    '524177': 'SBI', '608001': 'SBI', '608002': 'SBI', '608003': 'SBI', '608004': 'SBI',
    '608005': 'SBI', '438634': 'SBI', '438636': 'SBI', '459153': 'SBI', '524589': 'SBI',
    '531818': 'SBI', '539922': 'SBI', '542491': 'SBI', '545937': 'SBI', '549749': 'SBI',
    '607871': 'SBI', '607872': 'SBI', '403814': 'SBI', '405990': 'SBI',

    // ── HDFC Bank ──
    '400782': 'HDFC Bank', '401232': 'HDFC Bank', '438635': 'HDFC Bank', '526475': 'HDFC Bank',
    '541103': 'HDFC Bank', '485498': 'HDFC Bank', '463917': 'HDFC Bank', '552365': 'HDFC Bank',
    '545964': 'HDFC Bank', '222703': 'HDFC Bank', '405988': 'HDFC Bank', '426241': 'HDFC Bank',
    '462705': 'HDFC Bank', '416047': 'HDFC Bank', '454399': 'HDFC Bank', '462844': 'HDFC Bank',
    '407519': 'HDFC Bank', '536413': 'HDFC Bank', '528946': 'HDFC Bank', '518770': 'HDFC Bank',
    '652222': 'HDFC Bank', '652223': 'HDFC Bank', '607440': 'HDFC Bank', '607441': 'HDFC Bank',
    '607442': 'HDFC Bank', '607443': 'HDFC Bank', '402287': 'HDFC Bank', '403815': 'HDFC Bank',
    '407520': 'HDFC Bank', '416640': 'HDFC Bank', '434683': 'HDFC Bank', '440032': 'HDFC Bank',
    '447748': 'HDFC Bank', '451456': 'HDFC Bank', '462706': 'HDFC Bank', '518771': 'HDFC Bank',
    '528947': 'HDFC Bank', '536414': 'HDFC Bank', '541104': 'HDFC Bank', '545965': 'HDFC Bank',
    '552366': 'HDFC Bank', '607380': 'HDFC Bank', '607381': 'HDFC Bank', '652154': 'HDFC Bank',
    '652155': 'HDFC Bank',

    // ── ICICI Bank ──
    '409232': 'ICICI Bank', '437719': 'ICICI Bank', '517649': 'ICICI Bank', '546522': 'ICICI Bank',
    '431581': 'ICICI Bank', '437551': 'ICICI Bank', '524193': 'ICICI Bank', '405533': 'ICICI Bank',
    '405994': 'ICICI Bank', '222708': 'ICICI Bank', '222709': 'ICICI Bank', '416641': 'ICICI Bank',
    '406087': 'ICICI Bank', '416021': 'ICICI Bank', '447747': 'ICICI Bank', '447746': 'ICICI Bank',
    '514936': 'ICICI Bank', '552463': 'ICICI Bank', '652166': 'ICICI Bank', '652167': 'ICICI Bank',
    '607189': 'ICICI Bank', '607190': 'ICICI Bank', '607191': 'ICICI Bank', '400812': 'ICICI Bank',
    '403817': 'ICICI Bank', '406088': 'ICICI Bank', '416022': 'ICICI Bank', '431582': 'ICICI Bank',
    '437552': 'ICICI Bank', '447749': 'ICICI Bank', '514937': 'ICICI Bank', '517650': 'ICICI Bank',
    '524194': 'ICICI Bank', '546523': 'ICICI Bank', '552464': 'ICICI Bank', '607370': 'ICICI Bank',
    '607371': 'ICICI Bank', '652168': 'ICICI Bank', '652169': 'ICICI Bank',

    // ── Axis Bank ──
    '414720': 'Axis Bank', '415290': 'Axis Bank', '528387': 'Axis Bank', '540174': 'Axis Bank',
    '533467': 'Axis Bank', '451457': 'Axis Bank', '411146': 'Axis Bank', '450506': 'Axis Bank',
    '405267': 'Axis Bank', '405268': 'Axis Bank', '222819': 'Axis Bank', '403542': 'Axis Bank',
    '416027': 'Axis Bank', '423223': 'Axis Bank', '438628': 'Axis Bank', '441202': 'Axis Bank',
    '516730': 'Axis Bank', '524178': 'Axis Bank', '652158': 'Axis Bank', '652159': 'Axis Bank',
    '607393': 'Axis Bank', '607394': 'Axis Bank', '400813': 'Axis Bank', '403543': 'Axis Bank',
    '415291': 'Axis Bank', '423224': 'Axis Bank', '438637': 'Axis Bank', '441203': 'Axis Bank',
    '516731': 'Axis Bank', '528388': 'Axis Bank', '533468': 'Axis Bank', '540175': 'Axis Bank',
    '607395': 'Axis Bank', '607396': 'Axis Bank', '652160': 'Axis Bank', '652161': 'Axis Bank',

    // ── Kotak Mahindra Bank ──
    '415468': 'Kotak Mahindra Bank', '523956': 'Kotak Mahindra Bank', '403562': 'Kotak Mahindra Bank',
    '416634': 'Kotak Mahindra Bank', '416635': 'Kotak Mahindra Bank', '428221': 'Kotak Mahindra Bank',
    '434499': 'Kotak Mahindra Bank', '485472': 'Kotak Mahindra Bank', '527578': 'Kotak Mahindra Bank',
    '549771': 'Kotak Mahindra Bank', '652180': 'Kotak Mahindra Bank', '652181': 'Kotak Mahindra Bank',
    '607123': 'Kotak Mahindra Bank', '607124': 'Kotak Mahindra Bank', '400814': 'Kotak Mahindra Bank',
    '403563': 'Kotak Mahindra Bank', '416636': 'Kotak Mahindra Bank', '428222': 'Kotak Mahindra Bank',
    '434500': 'Kotak Mahindra Bank', '485473': 'Kotak Mahindra Bank', '527579': 'Kotak Mahindra Bank',
    '549772': 'Kotak Mahindra Bank', '607125': 'Kotak Mahindra Bank', '607126': 'Kotak Mahindra Bank',

    // ── Punjab National Bank (PNB) ──
    '405987': 'Punjab National Bank (PNB)', '416045': 'Punjab National Bank (PNB)',
    '436388': 'Punjab National Bank (PNB)', '447745': 'Punjab National Bank (PNB)',
    '504435': 'Punjab National Bank (PNB)', '526804': 'Punjab National Bank (PNB)',
    '607062': 'Punjab National Bank (PNB)', '607063': 'Punjab National Bank (PNB)',
    '652174': 'Punjab National Bank (PNB)', '652175': 'Punjab National Bank (PNB)',
    '508548': 'Punjab National Bank (PNB)', '400815': 'Punjab National Bank (PNB)',
    '405989': 'Punjab National Bank (PNB)', '416048': 'Punjab National Bank (PNB)',
    '436398': 'Punjab National Bank (PNB)', '447750': 'Punjab National Bank (PNB)',
    '504436': 'Punjab National Bank (PNB)', '526805': 'Punjab National Bank (PNB)',
    '607064': 'Punjab National Bank (PNB)', '607065': 'Punjab National Bank (PNB)',
    '652176': 'Punjab National Bank (PNB)', '508549': 'Punjab National Bank (PNB)',

    // ── Bank of Baroda (BOB) ──
    '403816': 'Bank of Baroda', '405986': 'Bank of Baroda', '416028': 'Bank of Baroda',
    '436389': 'Bank of Baroda', '520138': 'Bank of Baroda', '549770': 'Bank of Baroda',
    '607085': 'Bank of Baroda', '607086': 'Bank of Baroda', '652178': 'Bank of Baroda',
    '652179': 'Bank of Baroda', '508546': 'Bank of Baroda', '400816': 'Bank of Baroda',
    '403818': 'Bank of Baroda', '416049': 'Bank of Baroda', '436399': 'Bank of Baroda',
    '520139': 'Bank of Baroda', '549773': 'Bank of Baroda', '607087': 'Bank of Baroda',
    '607088': 'Bank of Baroda', '508547': 'Bank of Baroda',

    // ── Canara Bank ──
    '403876': 'Canara Bank', '405985': 'Canara Bank', '416046': 'Canara Bank',
    '436390': 'Canara Bank', '504642': 'Canara Bank', '549769': 'Canara Bank',
    '607101': 'Canara Bank', '607102': 'Canara Bank', '652182': 'Canara Bank',
    '652183': 'Canara Bank', '508550': 'Canara Bank', '400817': 'Canara Bank',
    '416050': 'Canara Bank', '436400': 'Canara Bank', '504643': 'Canara Bank',
    '549774': 'Canara Bank', '607103': 'Canara Bank', '607104': 'Canara Bank',

    // ── Union Bank of India ──
    '403877': 'Union Bank of India', '405984': 'Union Bank of India', '416029': 'Union Bank of India',
    '436391': 'Union Bank of India', '504434': 'Union Bank of India', '549768': 'Union Bank of India',
    '607117': 'Union Bank of India', '607118': 'Union Bank of India', '652186': 'Union Bank of India',
    '652187': 'Union Bank of India', '508544': 'Union Bank of India', '400818': 'Union Bank of India',
    '405992': 'Union Bank of India', '416051': 'Union Bank of India', '436401': 'Union Bank of India',
    '504437': 'Union Bank of India', '549775': 'Union Bank of India', '607119': 'Union Bank of India',

    // ── IndusInd Bank ──
    '403878': 'IndusInd Bank', '405983': 'IndusInd Bank', '416030': 'IndusInd Bank',
    '421387': 'IndusInd Bank', '512134': 'IndusInd Bank', '523951': 'IndusInd Bank',
    '549767': 'IndusInd Bank', '652190': 'IndusInd Bank', '652191': 'IndusInd Bank',
    '607231': 'IndusInd Bank', '607232': 'IndusInd Bank', '400819': 'IndusInd Bank',
    '405993': 'IndusInd Bank', '421388': 'IndusInd Bank', '549776': 'IndusInd Bank',

    // ── Yes Bank ──
    '403879': 'Yes Bank', '405982': 'Yes Bank', '416031': 'Yes Bank', '426242': 'Yes Bank',
    '549766': 'Yes Bank', '652194': 'Yes Bank', '652195': 'Yes Bank', '607245': 'Yes Bank',
    '607246': 'Yes Bank', '508560': 'Yes Bank', '400820': 'Yes Bank', '405995': 'Yes Bank',
    '426245': 'Yes Bank', '549777': 'Yes Bank', '607247': 'Yes Bank', '652196': 'Yes Bank',

    // ── Federal Bank / Fi / Jupiter ──
    '403880': 'Federal Bank', '405981': 'Federal Bank', '416032': 'Federal Bank',
    '434498': 'Federal Bank', '512136': 'Federal Bank', '523953': 'Federal Bank',
    '549765': 'Federal Bank', '652198': 'Federal Bank', '652199': 'Federal Bank',
    '607259': 'Federal Bank', '607260': 'Federal Bank', '400821': 'Federal Bank',
    '405996': 'Federal Bank', '434501': 'Federal Bank', '549778': 'Federal Bank',

    // ── IDFC FIRST Bank ──
    '403881': 'IDFC FIRST Bank', '405980': 'IDFC FIRST Bank', '416033': 'IDFC FIRST Bank',
    '485471': 'IDFC FIRST Bank', '512137': 'IDFC FIRST Bank', '523954': 'IDFC FIRST Bank',
    '549764': 'IDFC FIRST Bank', '652202': 'IDFC FIRST Bank', '652203': 'IDFC FIRST Bank',
    '607273': 'IDFC FIRST Bank', '607274': 'IDFC FIRST Bank', '400822': 'IDFC FIRST Bank',
    '405997': 'IDFC FIRST Bank', '485474': 'IDFC FIRST Bank', '549779': 'IDFC FIRST Bank',

    // ── RBL Bank ──
    '403882': 'RBL Bank', '405979': 'RBL Bank', '416034': 'RBL Bank', '512138': 'RBL Bank',
    '523955': 'RBL Bank', '549763': 'RBL Bank', '652206': 'RBL Bank', '652207': 'RBL Bank',
    '607287': 'RBL Bank', '607288': 'RBL Bank', '400823': 'RBL Bank', '405998': 'RBL Bank',

    // ── OneCard / FPL ──
    '403883': 'OneCard', '451458': 'OneCard', '524179': 'OneCard', '411147': 'OneCard',
    '405269': 'OneCard', '451462': 'OneCard', '451463': 'OneCard',

    // ── AU Small Finance Bank ──
    '403887': 'AU Small Finance Bank', '416038': 'AU Small Finance Bank', '426244': 'AU Small Finance Bank',
    '652210': 'AU Small Finance Bank', '607301': 'AU Small Finance Bank', '400824': 'AU Small Finance Bank',
    '405999': 'AU Small Finance Bank', '426246': 'AU Small Finance Bank', '607302': 'AU Small Finance Bank',

    // ── Bank of India (BOI) ──
    '403888': 'Bank of India', '405978': 'Bank of India', '416039': 'Bank of India',
    '436392': 'Bank of India', '504433': 'Bank of India', '607131': 'Bank of India',
    '607132': 'Bank of India', '652214': 'Bank of India', '508542': 'Bank of India',

    // ── Indian Bank ──
    '403889': 'Indian Bank', '405977': 'Indian Bank', '416040': 'Indian Bank',
    '436393': 'Indian Bank', '504432': 'Indian Bank', '607145': 'Indian Bank',
    '607146': 'Indian Bank', '652218': 'Indian Bank', '508540': 'Indian Bank',

    // ── Central Bank of India ──
    '403890': 'Central Bank of India', '405976': 'Central Bank of India', '416041': 'Central Bank of India',
    '436394': 'Central Bank of India', '504431': 'Central Bank of India', '607159': 'Central Bank of India',
    '607160': 'Central Bank of India', '652226': 'Central Bank of India', '508538': 'Central Bank of India',

    // ── Indian Overseas Bank (IOB) ──
    '403891': 'Indian Overseas Bank', '405975': 'Indian Overseas Bank', '416042': 'Indian Overseas Bank',
    '436395': 'Indian Overseas Bank', '504430': 'Indian Overseas Bank', '607173': 'Indian Overseas Bank',
    '607174': 'Indian Overseas Bank', '652230': 'Indian Overseas Bank', '508536': 'Indian Overseas Bank',

    // ── UCO Bank ──
    '403892': 'UCO Bank', '405974': 'UCO Bank', '416043': 'UCO Bank', '436396': 'UCO Bank',
    '504429': 'UCO Bank', '607187': 'UCO Bank', '607188': 'UCO Bank', '652234': 'UCO Bank',
    '508534': 'UCO Bank', '810001': 'UCO Bank', '820001': 'UCO Bank',

    // ── IDBI Bank ──
    '403893': 'IDBI Bank', '405973': 'IDBI Bank', '416044': 'IDBI Bank', '436397': 'IDBI Bank',
    '504428': 'IDBI Bank', '607201': 'IDBI Bank', '607202': 'IDBI Bank', '652238': 'IDBI Bank',
    '508532': 'IDBI Bank',

    // ── South Indian Bank ──
    '607215': 'South Indian Bank', '652242': 'South Indian Bank', '403894': 'South Indian Bank',

    // ── Karur Vysya Bank ──
    '607229': 'Karur Vysya Bank', '652246': 'Karur Vysya Bank', '403895': 'Karur Vysya Bank',

    // ── Karnataka Bank ──
    '607243': 'Karnataka Bank', '652250': 'Karnataka Bank', '403896': 'Karnataka Bank',

    // ── City Union Bank ──
    '607257': 'City Union Bank', '652254': 'City Union Bank', '403897': 'City Union Bank',

    // ── Bandhan Bank ──
    '607271': 'Bandhan Bank', '652258': 'Bandhan Bank', '403898': 'Bandhan Bank',

    // ── Standard Chartered ──
    '403884': 'Standard Chartered', '416035': 'Standard Chartered', '426243': 'Standard Chartered',
    '451459': 'Standard Chartered', '512139': 'Standard Chartered', '523957': 'Standard Chartered',
    '549762': 'Standard Chartered', '412211': 'Standard Chartered', '412212': 'Standard Chartered',
    '421318': 'Standard Chartered', '438638': 'Standard Chartered',

    // ── Citibank ──
    '412899': 'Citibank', '524249': 'Citibank', '403885': 'Citibank', '416036': 'Citibank',
    '438629': 'Citibank', '451460': 'Citibank', '549761': 'Citibank', '402288': 'Citibank',
    '431583': 'Citibank', '514938': 'Citibank', '541105': 'Citibank',

    // ── HSBC ──
    '403886': 'HSBC', '416037': 'HSBC', '438630': 'HSBC', '451461': 'HSBC',
    '512140': 'HSBC', '523958': 'HSBC', '549760': 'HSBC', '402289': 'HSBC',
    '431584': 'HSBC', '514939': 'HSBC', '541106': 'HSBC',

    // ── Chase / JP Morgan ──
    '414740': 'Chase', '444002': 'Chase', '514461': 'Chase', '414709': 'Chase',
    '424604': 'Chase', '424631': 'Chase', '438857': 'Chase', '474443': 'Chase',
    '485208': 'Chase', '424605': 'Chase', '438858': 'Chase', '474444': 'Chase',

    // ── Bank of America ──
    '402400': 'Bank of America', '412174': 'Bank of America', '426684': 'Bank of America',
    '431289': 'Bank of America', '435607': 'Bank of America', '441712': 'Bank of America',
    '474416': 'Bank of America', '480012': 'Bank of America', '518683': 'Bank of America',
    '520747': 'Bank of America', '546616': 'Bank of America', '402401': 'Bank of America',
    '412175': 'Bank of America', '431290': 'Bank of America', '441713': 'Bank of America',

    // ── Wells Fargo ──
    '400977': 'Wells Fargo', '409758': 'Wells Fargo', '412200': 'Wells Fargo',
    '414440': 'Wells Fargo', '427138': 'Wells Fargo', '446542': 'Wells Fargo',
    '473702': 'Wells Fargo', '520117': 'Wells Fargo', '543460': 'Wells Fargo',
    '400978': 'Wells Fargo', '409759': 'Wells Fargo', '414441': 'Wells Fargo',

    // ── Capital One ──
    '401676': 'Capital One', '414734': 'Capital One', '423225': 'Capital One',
    '438854': 'Capital One', '452033': 'Capital One', '461019': 'Capital One',
    '517805': 'Capital One', '529124': 'Capital One', '544747': 'Capital One',
    '401677': 'Capital One', '414735': 'Capital One', '438855': 'Capital One',

    // ── Barclays ──
    '475937': 'Barclays', '526593': 'Barclays', '492900': 'Barclays', '492901': 'Barclays',
    '492902': 'Barclays', '492920': 'Barclays', '475938': 'Barclays', '526594': 'Barclays',
    '492903': 'Barclays', '492921': 'Barclays',

    // ── American Express ──
    '374000': 'American Express', '375000': 'American Express', '376000': 'American Express',
    '377000': 'American Express', '378000': 'American Express', '379000': 'American Express',
    '340000': 'American Express', '371449': 'American Express', '378282': 'American Express',
  };

  /// Returns the issuing bank name, or 'Unknown' if not matched.
  static String detectBank(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return 'Unknown';

    // 1. Exact 6-digit BIN match
    if (d.length >= 6) {
      final bin6 = d.substring(0, 6);
      if (_binBankMap.containsKey(bin6)) {
        return _binBankMap[bin6]!;
      }
    }

    // 2. Prefix-level fallback detection
    if (d.startsWith('34') || d.startsWith('37')) {
      return 'American Express';
    }
    if (d.startsWith('6521') || d.startsWith('6522')) {
      return 'RuPay Domestic';
    }
    if (d.startsWith('508')) {
      return 'RuPay PMJDY / Domestic';
    }
    if (d.startsWith('60') && !d.startsWith('6011')) {
      return 'RuPay Domestic';
    }

    return 'Unknown';
  }

  // ─── Card Tier Detection from BIN ──────────────────────────────────────────

  static const Map<String, CardTier> _binTierMap = {
    // Infinite (Visa Infinite / MC World Elite / RuPay Select)
    '405994': CardTier.infinite, '400812': CardTier.infinite, '405988': CardTier.infinite,
    '405995': CardTier.infinite, '400820': CardTier.infinite, '400822': CardTier.infinite,
    '552365': CardTier.infinite, '552463': CardTier.infinite, '552366': CardTier.infinite,

    // Signature (Visa Signature / MC World)
    '485498': CardTier.signature, '463917': CardTier.signature, '433587': CardTier.signature,
    '405533': CardTier.signature, '411146': CardTier.signature, '416047': CardTier.signature,
    '485472': CardTier.signature, '485471': CardTier.signature, '510223': CardTier.signature,
    '533467': CardTier.signature, '485208': CardTier.signature, '480012': CardTier.signature,

    // Platinum (Visa Platinum / MC Platinum / RuPay Platinum)
    '431581': CardTier.platinum, '437551': CardTier.platinum, '451457': CardTier.platinum,
    '545964': CardTier.platinum, '524193': CardTier.platinum, '222703': CardTier.platinum,
    '652150': CardTier.platinum, '652151': CardTier.platinum, '652152': CardTier.platinum,
    '652154': CardTier.platinum, '652155': CardTier.platinum, '652158': CardTier.platinum,
    '652159': CardTier.platinum, '652166': CardTier.platinum, '652167': CardTier.platinum,
    '652174': CardTier.platinum, '652178': CardTier.platinum, '652182': CardTier.platinum,
    '652186': CardTier.platinum, '652190': CardTier.platinum, '652194': CardTier.platinum,
    '652198': CardTier.platinum, '652202': CardTier.platinum, '652206': CardTier.platinum,
    '652210': CardTier.platinum, '652214': CardTier.platinum, '652218': CardTier.platinum,
    '652222': CardTier.platinum, '652226': CardTier.platinum, '652230': CardTier.platinum,
    '652234': CardTier.platinum, '652238': CardTier.platinum, '405267': CardTier.platinum,
    '405268': CardTier.platinum, '406584': CardTier.platinum,

    // Gold (Visa Gold / MC Gold / Amex Gold)
    '400669': CardTier.gold, '400782': CardTier.gold, '409232': CardTier.gold,
    '414720': CardTier.gold, '524606': CardTier.gold, '526475': CardTier.gold,
    '517649': CardTier.gold, '528387': CardTier.gold, '374245': CardTier.gold,
  };

  /// Returns the detected [CardTier] based on the BIN or prefix.
  static CardTier detectTier(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 6) {
      final bin6 = d.substring(0, 6);
      if (_binTierMap.containsKey(bin6)) {
        return _binTierMap[bin6]!;
      }
    }

    // Prefix-level tier rules:
    if (d.startsWith('6521') || d.startsWith('6522')) return CardTier.platinum;
    if (d.startsWith('37') || d.startsWith('34')) return CardTier.gold;

    return CardTier.standard;
  }

  // ─── Card Type (Credit vs Debit) ───────────────────────────────────────────

  /// Returns 'Credit', 'Debit', or 'Unknown' if inferred from BIN.
  static String detectCardType(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.length < 6) return 'Unknown';
    final bin6 = d.substring(0, 6);

    // Well-known credit BINs
    const creditBins = {
      '485498', '463917', '552365', '545964', '222703', '510223', '433587',
      '405450', '431581', '437551', '524193', '405533', '533467', '451457',
      '411146', '450506', '485472', '485471', '403883', '451458', '524179',
    };

    if (creditBins.contains(bin6)) return 'Credit';
    if (d.startsWith('34') || d.startsWith('37')) return 'Credit'; // Amex cards
    if (d.startsWith('508') || d.startsWith('60')) return 'Debit'; // RuPay domestic

    return 'Unknown';
  }

  // ─── Gradient Brand Colors ─────────────────────────────────────────────────

  static const Map<String, List<String>> _bankColors = {
    'SBI':                        ['#004B87', '#1A73E8'],
    'State Bank of India (SBI)':  ['#004B87', '#1A73E8'],
    'HDFC Bank':                  ['#004C8F', '#00264D'],
    'ICICI Bank':                 ['#A32A29', '#E65100'],
    'Axis Bank':                  ['#800032', '#97144D'],
    'Kotak Mahindra Bank':        ['#ED1C24', '#003366'],
    'Punjab National Bank (PNB)': ['#9B1C26', '#E22028'],
    'Bank of Baroda':             ['#F26522', '#F7931E'],
    'Canara Bank':                ['#0091DA', '#FFD100'],
    'Union Bank of India':        ['#004A99', '#DA291C'],
    'IndusInd Bank':              ['#800000', '#A52A2A'],
    'Yes Bank':                   ['#003366', '#0055A5'],
    'Federal Bank':               ['#003366', '#FFB81C'],
    'IDFC FIRST Bank':            ['#9C1D26', '#72121B'],
    'RBL Bank':                   ['#003876', '#E31B23'],
    'OneCard':                    ['#1E1E1E', '#3A3A3A'],
    'AU Small Finance Bank':      ['#7A1C7D', '#5E1460'],
    'Bank of India':              ['#E31837', '#004990'],
    'Indian Bank':                ['#005696', '#E41B13'],
    'Central Bank of India':      ['#005A9C', '#C41230'],
    'Indian Overseas Bank':       ['#004380', '#0072CE'],
    'UCO Bank':                   ['#004B87', '#0078D7'],
    'IDBI Bank':                  ['#006838', '#F37023'],
    'South Indian Bank':          ['#003366', '#E31B23'],
    'Karur Vysya Bank':           ['#9C1D26', '#E28D1B'],
    'Karnataka Bank':             ['#003366', '#007ACC'],
    'City Union Bank':            ['#004A99', '#E65100'],
    'Bandhan Bank':               ['#003366', '#E41B13'],
    'Standard Chartered':         ['#009A44', '#005826'],
    'Citibank':                   ['#003B70', '#0070BA'],
    'HSBC':                       ['#DB0011', '#000000'],
    'Chase':                      ['#117ACA', '#0B4D82'],
    'Bank of America':            ['#DC143C', '#002D62'],
    'Wells Fargo':                ['#D71E28', '#CD1409'],
    'Capital One':                ['#004977', '#D03027'],
    'Barclays':                   ['#00AEEF', '#00395D'],
    'American Express':           ['#002663', '#0077A6'],
    'RuPay Domestic':             ['#00796B', '#004D40'],
    'RuPay PMJDY / Domestic':     ['#00796B', '#004D40'],
    'Unknown':                    ['#1E293B', '#334155'],
  };

  static const List<List<String>> _curatedGradients = [
    ['#1E3A8A', '#0D9488'], // Deep Sapphire to Ocean Teal
    ['#4C1D95', '#BE185D'], // Regal Violet to Magenta
    ['#065F46', '#047857'], // Emerald Forest
    ['#831843', '#BE123C'], // Ruby Velvet
    ['#0F172A', '#334155'], // Graphite Slate
    ['#7C2D12', '#EA580C'], // Copper Bronze
    ['#1E1B4B', '#4338CA'], // Midnight Indigo
    ['#701A75', '#A21CAF'], // Amethyst
    ['#0F766E', '#0284C7'], // Caribbean Blue
    ['#312E81', '#1D4ED8'], // Deep Cobalt
    ['#14532D', '#15803D'], // Jade Green
    ['#3B0764', '#7E22CE'], // Royal Purple
  ];

  /// Returns a list of two hex color strings representing the bank's gradient.
  /// Uses fuzzy keyword matching and falls back to a deterministic luxury gradient.
  static List<String> getBankColors(String bankName) {
    final clean = bankName.trim().toLowerCase();
    if (clean.isEmpty) return _curatedGradients[0];

    // 1. Direct match
    if (_bankColors.containsKey(bankName)) return _bankColors[bankName]!;

    // 2. Keyword matching
    if (clean.contains('sbi') || clean.contains('state bank')) return _bankColors['SBI']!;
    if (clean.contains('hdfc')) return _bankColors['HDFC Bank']!;
    if (clean.contains('icici')) return _bankColors['ICICI Bank']!;
    if (clean.contains('axis')) return _bankColors['Axis Bank']!;
    if (clean.contains('kotak')) return _bankColors['Kotak Mahindra Bank']!;
    if (clean.contains('pnb') || clean.contains('punjab')) return _bankColors['Punjab National Bank (PNB)']!;
    if (clean.contains('baroda') || clean.contains('bob')) return _bankColors['Bank of Baroda']!;
    if (clean.contains('canara')) return _bankColors['Canara Bank']!;
    if (clean.contains('union bank')) return _bankColors['Union Bank of India']!;
    if (clean.contains('indusind')) return _bankColors['IndusInd Bank']!;
    if (clean.contains('yes bank')) return _bankColors['Yes Bank']!;
    if (clean.contains('idfc')) return _bankColors['IDFC FIRST Bank']!;
    if (clean.contains('federal')) return _bankColors['Federal Bank']!;
    if (clean.contains('rbl')) return _bankColors['RBL Bank']!;
    if (clean.contains('onecard')) return _bankColors['OneCard']!;
    if (clean.contains('au small') || clean.contains('aubank')) return _bankColors['AU Small Finance Bank']!;
    if (clean.contains('bank of india') || clean.contains('boi')) return _bankColors['Bank of India']!;
    if (clean.contains('indian bank')) return _bankColors['Indian Bank']!;
    if (clean.contains('central bank')) return _bankColors['Central Bank of India']!;
    if (clean.contains('iob') || clean.contains('indian overseas')) return _bankColors['Indian Overseas Bank']!;
    if (clean.contains('uco')) return _bankColors['UCO Bank']!;
    if (clean.contains('idbi')) return _bankColors['IDBI Bank']!;
    if (clean.contains('south indian')) return _bankColors['South Indian Bank']!;
    if (clean.contains('karur vysya') || clean.contains('kvb')) return _bankColors['Karur Vysya Bank']!;
    if (clean.contains('karnataka')) return _bankColors['Karnataka Bank']!;
    if (clean.contains('city union')) return _bankColors['City Union Bank']!;
    if (clean.contains('bandhan')) return _bankColors['Bandhan Bank']!;
    if (clean.contains('standard chartered') || clean.contains('stan')) return _bankColors['Standard Chartered']!;
    if (clean.contains('citi')) return _bankColors['Citibank']!;
    if (clean.contains('hsbc')) return _bankColors['HSBC']!;
    if (clean.contains('chase')) return _bankColors['Chase']!;
    if (clean.contains('amex') || clean.contains('american express')) return _bankColors['American Express']!;
    if (clean.contains('rupay')) return _bankColors['RuPay Domestic']!;

    // 3. Deterministic luxury jewel gradient based on bankName hash
    final hash = clean.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _curatedGradients[hash % _curatedGradients.length];
  }

  /// Returns Flutter [Color] gradient for the card based on bank and tier.
  static List<Color> getCardGradient(String bankName, CardTier tier) {
    if (tier == CardTier.gold) {
      return [const Color(0xFFD4AF37), const Color(0xFFAA771C), const Color(0xFF432A02)];
    }
    if (tier == CardTier.platinum) {
      return [const Color(0xFFE5E4E2), const Color(0xFF78909C), const Color(0xFF263238)];
    }
    if (tier == CardTier.infinite) {
      return [const Color(0xFF1E1E24), const Color(0xFF101014), const Color(0xFF000000)];
    }
    if (tier == CardTier.signature) {
      return [const Color(0xFF3B0764), const Color(0xFF6B21A8), const Color(0xFF1E1B4B)];
    }

    final hexList = getBankColors(bankName);
    return hexList.map((h) {
      final hex = h.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    }).toList();
  }

  // ─── Network Logo / Emoji ──────────────────────────────────────────────────

  static const Map<String, String> _networkEmoji = {
    'Visa':       '💳',
    'Mastercard': '🔴',
    'Amex':       '🟦',
    'Discover':   '🟠',
    'RuPay':      '🇮🇳',
    'JCB':        '🟩',
    'Diners':     '🔷',
    'UnionPay':   '🟥',
    'Maestro':    '💳',
    'Unknown':    '💳',
  };

  static String getNetworkEmoji(String network) {
    return _networkEmoji[network] ?? '💳';
  }

  // ─── Full Detection Result ─────────────────────────────────────────────────

  /// Returns a [CardDetectionResult] with all derived information.
  static CardDetectionResult detect(String number) {
    final network = detectNetwork(number);
    final bank = detectBank(number);
    final tier = detectTier(number);
    final cardType = detectCardType(number);

    return CardDetectionResult(
      network: network,
      bank: bank,
      tier: tier,
      cardType: cardType,
      bankColors: getBankColors(bank),
      networkEmoji: getNetworkEmoji(network),
      isValid: luhnCheck(number),
    );
  }
}

/// Holds all derived information for a card number.
class CardDetectionResult {
  final String network;
  final String bank;
  final CardTier tier;
  final String cardType;
  final List<String> bankColors;
  final String networkEmoji;
  final bool isValid;

  const CardDetectionResult({
    required this.network,
    required this.bank,
    this.tier = CardTier.standard,
    this.cardType = 'Unknown',
    required this.bankColors,
    required this.networkEmoji,
    required this.isValid,
  });
}

/// Converts a hex colour string (e.g. '#1a237e') to a [Color].
Color hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
