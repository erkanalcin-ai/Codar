enum ReaderProgressDisplayMode {
  pageAndPercent('page_and_percent'),
  pageOnly('page_only'),
  percentOnly('percent_only'),
  hidden('hidden');

  const ReaderProgressDisplayMode(this.storageValue);

  final String storageValue;

  static ReaderProgressDisplayMode fromStored(String? value) =>
      ReaderProgressDisplayMode.values.firstWhere(
        (mode) => mode.storageValue == value,
        orElse: () => ReaderProgressDisplayMode.pageAndPercent,
      );

  bool get showsPage =>
      this == ReaderProgressDisplayMode.pageAndPercent ||
      this == ReaderProgressDisplayMode.pageOnly;

  bool get showsPercent =>
      this == ReaderProgressDisplayMode.pageAndPercent ||
      this == ReaderProgressDisplayMode.percentOnly;
}
