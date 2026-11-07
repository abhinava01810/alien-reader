import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

/// Turns text into a WAV file on the phone. Abstracted for tests.
abstract interface class SpeechFileSynthesizer {
  /// Writes speech for [text] to [outputPath] (WAV). Throws on failure.
  Future<void> synthesize(String text, String outputPath);
}

/// The phone's own text-to-speech engine (normally Google's neural voices),
/// recorded to a file. Replaces the Pi's eSpeak audio for phone-processed
/// captures. Only voices that run offline are used, so the text is not sent
/// to a speech server.
class DeviceSpeechSynthesizer implements SpeechFileSynthesizer {
  DeviceSpeechSynthesizer({FlutterTts? tts, this.speechRate = 0.5})
    : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// flutter_tts scale: 0.5 is the engine's normal speed on Android.
  final double speechRate;

  /// Android rejects longer single requests (TextToSpeech
  /// getMaxSpeechInputLength is 4000); stay well under it.
  static const int maxChunkChars = 3000;

  bool _ready = false;

  /// The voice chosen on first use, for diagnostics.
  Map<String, String>? chosenVoice;

  Future<void> _prepare() async {
    if (_ready) return;
    await _tts.awaitSynthCompletion(true);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    try {
      final voices = await _tts.getVoices;
      final best = pickBestVoice(voices is List ? voices : const []);
      if (best != null) {
        await _tts.setVoice({'name': best['name']!, 'locale': best['locale']!});
        chosenVoice = best;
      }
    } catch (_) {
      // Keep the engine's default English voice.
    }
    _ready = true;
  }

  /// Highest-quality offline US-English voice, then any offline English.
  static Map<String, String>? pickBestVoice(List<dynamic> voices) {
    const rank = {'very high': 5, 'high': 4, 'normal': 3, 'low': 2};
    final usable = voices
        .whereType<Map>()
        .map((v) => v.map((k, val) => MapEntry('$k', '$val')))
        .where(
          (v) =>
              v['name'] != null &&
              v['locale'] != null &&
              v['network_required'] != '1' &&
              !(v['features'] ?? '').contains('notInstalled') &&
              v['locale']!.toLowerCase().startsWith('en'),
        )
        .toList();
    if (usable.isEmpty) return null;
    int score(Map<String, String> v) {
      final us = v['locale']!.toLowerCase().replaceAll('_', '-') == 'en-us';
      return (rank[v['quality']] ?? 0) * 10 + (us ? 5 : 0);
    }

    usable.sort((a, b) => score(b).compareTo(score(a)));
    return usable.first;
  }

  @override
  Future<void> synthesize(String text, String outputPath) async {
    await _prepare();
    final chunks = splitForSpeech(text, maxChunkChars);
    if (chunks.isEmpty) throw const SpeechException('Nothing to speak.');

    final out = File(outputPath);
    await out.parent.create(recursive: true);
    if (chunks.length == 1) {
      await _synthOne(chunks.single, outputPath);
      return;
    }
    final parts = <File>[];
    try {
      for (var i = 0; i < chunks.length; i++) {
        final part = '$outputPath.part$i.wav';
        await _synthOne(chunks[i], part);
        parts.add(File(part));
      }
      final joined = concatWav([for (final p in parts) await p.readAsBytes()]);
      await out.writeAsBytes(joined, flush: true);
    } finally {
      for (final p in parts) {
        if (p.existsSync()) p.deleteSync();
      }
    }
  }

  Future<void> _synthOne(String text, String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    // isFullPath = true keeps the file in app storage; without it the
    // plugin would write into the shared Music folder.
    final result = await _tts.synthesizeToFile(text, path, true);
    if (result != 1 || !file.existsSync() || file.lengthSync() <= 44) {
      throw const SpeechException('The phone could not create the audio.');
    }
  }
}

/// Splits on paragraph, then sentence, then word boundaries so each piece
/// is at most [max] characters.
List<String> splitForSpeech(String text, int max) {
  final clean = text.trim();
  if (clean.isEmpty) return const [];
  final pieces = <String>[];
  var buffer = StringBuffer();

  void flush() {
    final s = buffer.toString().trim();
    if (s.isNotEmpty) pieces.add(s);
    buffer = StringBuffer();
  }

  void add(String unit, String sep) {
    if (unit.length > max) {
      flush();
      // A single sentence longer than max: break on spaces.
      var line = StringBuffer();
      for (final word in unit.split(' ')) {
        if (line.length + word.length + 1 > max && line.isNotEmpty) {
          pieces.add(line.toString().trim());
          line = StringBuffer();
        }
        if (word.length > max) {
          for (var i = 0; i < word.length; i += max) {
            pieces.add(word.substring(i, (i + max).clamp(0, word.length)));
          }
        } else {
          line
            ..write(word)
            ..write(' ');
        }
      }
      final rest = line.toString().trim();
      if (rest.isNotEmpty) pieces.add(rest);
      return;
    }
    if (buffer.length + unit.length + sep.length > max) flush();
    if (buffer.isNotEmpty) buffer.write(sep);
    buffer.write(unit);
  }

  for (final para in clean.split(RegExp(r'\n\s*\n'))) {
    final sentences = para
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty);
    for (final s in sentences) {
      add(s.trim(), ' ');
    }
    if (buffer.isNotEmpty) buffer.write('\n\n');
  }
  flush();
  return pieces;
}

/// Joins WAV files with the same format into one: keeps the first file's
/// format chunk and concatenates every file's PCM data.
Uint8List concatWav(List<Uint8List> files) {
  if (files.isEmpty) throw const SpeechException('No audio to join.');
  Uint8List? fmt;
  final data = BytesBuilder(copy: false);
  for (final f in files) {
    final bd = ByteData.sublistView(f);
    if (f.length < 12 ||
        String.fromCharCodes(f.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(f.sublist(8, 12)) != 'WAVE') {
      throw const SpeechException('Unexpected audio format.');
    }
    var pos = 12;
    while (pos + 8 <= f.length) {
      final id = String.fromCharCodes(f.sublist(pos, pos + 4));
      var size = bd.getUint32(pos + 4, Endian.little);
      final start = pos + 8;
      // Some engines leave the data size as 0/garbage while streaming.
      if (id == 'data' && (size == 0 || start + size > f.length)) {
        size = f.length - start;
      }
      final end = (start + size).clamp(0, f.length);
      if (id == 'fmt ') fmt ??= f.sublist(start, end);
      if (id == 'data') data.add(f.sublist(start, end));
      pos = end + (size.isOdd ? 1 : 0);
    }
  }
  if (fmt == null) throw const SpeechException('Audio had no format chunk.');
  final pcm = data.takeBytes();
  final out = BytesBuilder();
  final header = ByteData(12);
  final fmtChunk = ByteData(8);
  final dataHeader = ByteData(8);
  final riffSize = 4 + (8 + fmt.length) + (8 + pcm.length);
  out.add('RIFF'.codeUnits);
  header.setUint32(0, riffSize, Endian.little);
  out.add(header.buffer.asUint8List(0, 4));
  out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits);
  fmtChunk.setUint32(0, fmt.length, Endian.little);
  out.add(fmtChunk.buffer.asUint8List(0, 4));
  out.add(fmt);
  out.add('data'.codeUnits);
  dataHeader.setUint32(0, pcm.length, Endian.little);
  out.add(dataHeader.buffer.asUint8List(0, 4));
  out.add(pcm);
  return out.takeBytes();
}

class SpeechException implements Exception {
  const SpeechException(this.message);
  final String message;
  @override
  String toString() => message;
}
