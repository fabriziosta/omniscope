/// Metadata for a traditional / equity broker venue.
class BrokerExchange {
  const BrokerExchange({
    required this.id,
    required this.displayName,
    this.description = '',
  });

  final String id;
  final String displayName;
  final String description;
}
