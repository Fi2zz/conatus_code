import 'package:conatus_code/safety.dart';
import 'package:test/test.dart';

void main() {
  test('私钥命中与变体', () {
    for (final String p in <String>[
      '/home/u/.ssh/id_rsa',
      '/home/u/.ssh/id_ed25519',
      '/home/u/.ssh/id_rsa.bak',
      '/home/u/.ssh/id_rsa_old',
      '/home/u/.ssh/id_rsa-copy',
    ]) {
      expect(matchSensitivePath(p)?.kind, SensitiveKind.privateKey, reason: p);
    }
  });

  test('公钥与 .env 豁免放行', () {
    expect(matchSensitivePath('/home/u/.ssh/id_rsa.pub'), isNull);
    expect(matchSensitivePath('/work/.env.example'), isNull);
    expect(matchSensitivePath('/work/.env.sample'), isNull);
  });

  test('凭据与 .env 族', () {
    expect(
      matchSensitivePath('/work/credentials')?.kind,
      SensitiveKind.credentials,
    );
    expect(
      matchSensitivePath('/home/u/.aws/credentials')?.kind,
      SensitiveKind.credentials,
    );
    expect(
      matchSensitivePath('/home/u/.gcp/credentials')?.kind,
      SensitiveKind.credentials,
    );
    expect(matchSensitivePath('/work/.env')?.kind, SensitiveKind.dotenv);
    expect(matchSensitivePath('/work/.env.local')?.kind, SensitiveKind.dotenv);
  });

  test('Windows 分隔符与大小写', () {
    expect(
      matchSensitivePath(r'C:\Users\u\.ssh\ID_RSA')?.kind,
      SensitiveKind.privateKey,
    );
    expect(matchSensitivePath(r'C:\work\.ENV')?.kind, SensitiveKind.dotenv);
  });

  test('extraPaths 支持名称与路径段', () {
    expect(
      matchSensitivePath(
        '/work/secrets/token.txt',
        extraPaths: <String>{'secrets'},
      )?.kind,
      SensitiveKind.extra,
    );
    expect(
      matchSensitivePath(
        '/work/token.txt',
        extraPaths: <String>{'token.txt'},
      )?.kind,
      SensitiveKind.extra,
    );
    expect(
      matchSensitivePath(
        '/work/secrets/token.txt',
        extraPaths: <String>{'/work/secrets'},
      )?.kind,
      SensitiveKind.extra,
    );
  });
}
