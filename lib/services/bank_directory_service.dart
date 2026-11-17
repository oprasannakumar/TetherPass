/// Comprehensive Bank Directory Service with fast alias & acronym matching.
/// Standardizes bank names (e.g. 'PNB' -> 'Punjab National Bank', 'SBI' -> 'State Bank of India')
/// to ensure uniform database sync, BIN matching, and clean card vault display.
class BankEntry {
  final String name;
  final List<String> aliases;
  final String? category;

  const BankEntry({
    required this.name,
    this.aliases = const [],
    this.category,
  });

  String get displayName => aliases.isNotEmpty ? '$name (${aliases.first})' : name;
}

class BankDirectoryService {
  BankDirectoryService._();

  static const List<BankEntry> banks = [
    // ── Public Sector Banks (India) ──
    BankEntry(
      name: 'State Bank of India',
      aliases: ['SBI', 'State Bank'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Punjab National Bank',
      aliases: ['PNB', 'Punjab National'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Bank of Baroda',
      aliases: ['BOB', 'Baroda'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Canara Bank',
      aliases: ['Canara', 'Syndicate'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Union Bank of India',
      aliases: ['UBI', 'Union Bank', 'Andhra Bank', 'Corporation Bank'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Bank of India',
      aliases: ['BOI'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Indian Bank',
      aliases: ['Allahabad Bank'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Central Bank of India',
      aliases: ['CBI', 'Central Bank'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Indian Overseas Bank',
      aliases: ['IOB'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'UCO Bank',
      aliases: ['UCO'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Bank of Maharashtra',
      aliases: ['BOM', 'Maha Bank'],
      category: 'Public Sector Bank',
    ),
    BankEntry(
      name: 'Punjab & Sind Bank',
      aliases: ['PSB', 'Punjab and Sind'],
      category: 'Public Sector Bank',
    ),

    // ── Major Private Sector Banks (India) ──
    BankEntry(
      name: 'HDFC Bank',
      aliases: ['HDFC'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'ICICI Bank',
      aliases: ['ICICI'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Axis Bank',
      aliases: ['Axis', 'UTI Bank'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Kotak Mahindra Bank',
      aliases: ['Kotak', 'Kotak Bank'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'IndusInd Bank',
      aliases: ['IndusInd'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'IDFC FIRST Bank',
      aliases: ['IDFC', 'IDFC Bank', 'IDFC First'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Yes Bank',
      aliases: ['YES'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Federal Bank',
      aliases: ['Federal'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'RBL Bank',
      aliases: ['RBL', 'Ratnakar'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Bandhan Bank',
      aliases: ['Bandhan'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'IDBI Bank',
      aliases: ['IDBI'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'South Indian Bank',
      aliases: ['SIB'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Karur Vysya Bank',
      aliases: ['KVB'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'City Union Bank',
      aliases: ['CUB'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Karnataka Bank',
      aliases: ['KBL'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Tamilnad Mercantile Bank',
      aliases: ['TMB'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Jammu & Kashmir Bank',
      aliases: ['J&K Bank', 'JKB'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'CSB Bank',
      aliases: ['CSB', 'Catholic Syrian'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Dhanlaxmi Bank',
      aliases: ['Dhanlaxmi'],
      category: 'Private Sector Bank',
    ),
    BankEntry(
      name: 'Nainital Bank',
      aliases: ['Nainital'],
      category: 'Private Sector Bank',
    ),

    // ── Small Finance & Payments Banks (India) ──
    BankEntry(
      name: 'AU Small Finance Bank',
      aliases: ['AU Bank', 'AU Small'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Equitas Small Finance Bank',
      aliases: ['Equitas'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Ujjivan Small Finance Bank',
      aliases: ['Ujjivan'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Jana Small Finance Bank',
      aliases: ['Jana'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Capital Small Finance Bank',
      aliases: ['Capital'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'ESAF Small Finance Bank',
      aliases: ['ESAF'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Fincare Small Finance Bank',
      aliases: ['Fincare'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Suryoday Small Finance Bank',
      aliases: ['Suryoday'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Utkarsh Small Finance Bank',
      aliases: ['Utkarsh'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Shivalik Small Finance Bank',
      aliases: ['Shivalik'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'North East Small Finance Bank',
      aliases: ['NESFB'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Unity Small Finance Bank',
      aliases: ['Unity'],
      category: 'Small Finance Bank',
    ),
    BankEntry(
      name: 'Airtel Payments Bank',
      aliases: ['Airtel'],
      category: 'Payments Bank',
    ),
    BankEntry(
      name: 'India Post Payments Bank',
      aliases: ['IPPB', 'Post Office'],
      category: 'Payments Bank',
    ),
    BankEntry(
      name: 'Paytm Payments Bank',
      aliases: ['Paytm'],
      category: 'Payments Bank',
    ),
    BankEntry(
      name: 'Fino Payments Bank',
      aliases: ['Fino'],
      category: 'Payments Bank',
    ),
    BankEntry(
      name: 'Jio Payments Bank',
      aliases: ['Jio'],
      category: 'Payments Bank',
    ),

    // ── Co-branded Fintechs & Neo-Cards ──
    BankEntry(
      name: 'OneCard',
      aliases: ['One Card', 'FPL'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Jupiter',
      aliases: ['Jupiter Federal'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Fi Money',
      aliases: ['Fi', 'Fi Federal'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Scapia',
      aliases: ['Scapia Federal'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Tata Neu',
      aliases: ['Tata Neu HDFC'],
      category: 'Co-Branded Card',
    ),
    BankEntry(
      name: 'Slice',
      aliases: ['Slice Card'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Uni Card',
      aliases: ['Uni'],
      category: 'Fintech Card',
    ),
    BankEntry(
      name: 'Niyo',
      aliases: ['Niyo Global'],
      category: 'Fintech Card',
    ),

    // ── International & Foreign Banks ──
    BankEntry(
      name: 'Citibank',
      aliases: ['Citi'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Standard Chartered Bank',
      aliases: ['StanC', 'SCB', 'Standard Chartered'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'HSBC',
      aliases: ['Hongkong and Shanghai'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Barclays',
      aliases: ['Barclays Bank'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Deutsche Bank',
      aliases: ['Deutsche'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'DBS Bank',
      aliases: ['DBS', 'Digibank'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'JPMorgan Chase',
      aliases: ['Chase', 'JPMC', 'JP Morgan'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Bank of America',
      aliases: ['BofA', 'BOA'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Wells Fargo',
      aliases: ['Wells'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'American Express',
      aliases: ['Amex'],
      category: 'Financial Services',
    ),
    BankEntry(
      name: 'Discover',
      aliases: ['Discover Bank'],
      category: 'Financial Services',
    ),
    BankEntry(
      name: 'Capital One',
      aliases: ['CapOne'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'SBM Bank',
      aliases: ['State Bank of Mauritius'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'BNP Paribas',
      aliases: ['BNP'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Royal Bank of Canada',
      aliases: ['RBC'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Toronto-Dominion Bank',
      aliases: ['TD Bank', 'TD'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Commonwealth Bank of Australia',
      aliases: ['CBA', 'CommBank'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'ANZ Bank',
      aliases: ['ANZ'],
      category: 'International Bank',
    ),
    BankEntry(
      name: 'Santander',
      aliases: ['Banco Santander'],
      category: 'International Bank',
    ),
  ];

  /// Fast search for banks matching [query] across name, acronyms, and aliases.
  /// Prioritizes exact alias matches (e.g. 'PNB' -> Punjab National Bank) and prefix matches.
  static List<BankEntry> search(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final exactAliasMatches = <BankEntry>[];
    final prefixAliasMatches = <BankEntry>[];
    final prefixNameMatches = <BankEntry>[];
    final substringMatches = <BankEntry>[];

    for (final entry in banks) {
      final nameLower = entry.name.toLowerCase();
      final aliasLowers = entry.aliases.map((a) => a.toLowerCase()).toList();

      // 1. Exact alias match (e.g. 'pnb' == 'pnb', 'sbi' == 'sbi')
      if (aliasLowers.contains(clean)) {
        exactAliasMatches.add(entry);
        continue;
      }

      // 2. Exact name match
      if (nameLower == clean) {
        exactAliasMatches.add(entry);
        continue;
      }

      // 3. Prefix match on aliases
      if (aliasLowers.any((a) => a.startsWith(clean))) {
        prefixAliasMatches.add(entry);
        continue;
      }

      // 4. Prefix match on canonical name or words in name
      final words = nameLower.split(RegExp(r'\s+'));
      if (nameLower.startsWith(clean) || words.any((w) => w.startsWith(clean))) {
        prefixNameMatches.add(entry);
        continue;
      }

      // 5. General substring match
      if (nameLower.contains(clean) || aliasLowers.any((a) => a.contains(clean))) {
        substringMatches.add(entry);
      }
    }

    final combined = <BankEntry>[
      ...exactAliasMatches,
      ...prefixAliasMatches,
      ...prefixNameMatches,
      ...substringMatches,
    ];

    // Return top 8 deduplicated matches
    final seen = <String>{};
    final result = <BankEntry>[];
    for (final b in combined) {
      if (seen.add(b.name)) {
        result.add(b);
        if (result.length >= 8) break;
      }
    }
    return result;
  }

  /// Automatically normalizes user input or abbreviation (e.g. 'sbi' -> 'State Bank of India')
  /// into its standardized canonical bank name for universal database sync.
  static String normalizeBankName(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return clean;

    final lower = clean.toLowerCase();
    for (final entry in banks) {
      if (entry.name.toLowerCase() == lower) {
        return entry.name;
      }
      for (final a in entry.aliases) {
        if (a.toLowerCase() == lower) {
          return entry.name;
        }
      }
    }

    // Common specific edge cases
    if (lower == 'sbi' || lower == 'state bank') return 'State Bank of India';
    if (lower == 'pnb' || lower == 'punjab national') return 'Punjab National Bank';
    if (lower == 'bob' || lower == 'baroda') return 'Bank of Baroda';
    if (lower == 'boi') return 'Bank of India';
    if (lower == 'ubi' || lower == 'union bank') return 'Union Bank of India';
    if (lower == 'cbi' || lower == 'central bank') return 'Central Bank of India';
    if (lower == 'bom' || lower == 'bank of maharashtra') return 'Bank of Maharashtra';
    if (lower == 'psb') return 'Punjab & Sind Bank';
    if (lower == 'iob') return 'Indian Overseas Bank';
    if (lower == 'hdfc') return 'HDFC Bank';
    if (lower == 'icici') return 'ICICI Bank';
    if (lower == 'axis') return 'Axis Bank';
    if (lower == 'kotak') return 'Kotak Mahindra Bank';
    if (lower == 'idfc' || lower == 'idfc first') return 'IDFC FIRST Bank';
    if (lower == 'rbl') return 'RBL Bank';
    if (lower == 'citi') return 'Citibank';
    if (lower == 'amex') return 'American Express';
    if (lower == 'chase') return 'JPMorgan Chase';
    if (lower == 'bofa') return 'Bank of America';
    if (lower == 'stanc') return 'Standard Chartered Bank';

    return clean;
  }
}
