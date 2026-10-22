import 'package:app_web_ui/services/web_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const srt = '''1
00:05:10,160 --> 00:05:13,152
<i>Sir, please put down
the spear.</i>

2
00:05:50,880 --> 00:05:51,995
You have heart.
''';

  const vtt = '''WEBVTT

00:01.000 --> 00:03.500 align:center
Short <b>hours</b> form

01:00:00.000 --> 01:00:02.000
An hour in
''';

  test('parses SRT, strips tags, keeps line breaks', () {
    final cues = parseSubtitles(srt);
    expect(cues, hasLength(2));
    expect(cues[0].start, closeTo(310.16, 0.001));
    expect(cues[0].end, closeTo(313.152, 0.001));
    expect(cues[0].text, 'Sir, please put down\nthe spear.');
  });

  test('parses WebVTT with and without hours', () {
    final cues = parseSubtitles(vtt);
    expect(cues.map((c) => c.start), [1.0, 3600.0]);
    expect(cues[0].text, 'Short hours form');
  });

  test('cueAt finds the cue on screen, or none in a gap', () {
    final cues = parseSubtitles(srt);
    expect(cueAt(cues, 311)?.text, startsWith('Sir'));
    expect(cueAt(cues, 330), isNull);
    expect(cueAt(cues, 351.5)?.text, 'You have heart.');
    expect(cueAt(cues, 1), isNull);
  });

  test('handles CRLF files', () {
    final cues = parseSubtitles(srt.replaceAll('\n', '\r\n'));
    expect(cues, hasLength(2));
  });
}
