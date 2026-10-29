enum ReaderConnectionStatus { disconnected, connecting, connected, busy }

abstract class ReaderDevice {
  Stream<ReaderConnectionStatus> get status;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> capture();

  Future<void> finishScan();

  Future<List<String>> getFiles();
}
