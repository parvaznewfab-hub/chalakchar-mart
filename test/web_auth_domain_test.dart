import 'package:chalakchar_mart/utils/web_auth_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('own hosts use themselves as authDomain', () {
    expect(authDomainForHost('chalakcharmart.com'), 'chalakcharmart.com');
    expect(authDomainForHost('www.chalakcharmart.com'), 'www.chalakcharmart.com');
    expect(authDomainForHost('chalakchar-mart.web.app'), 'chalakchar-mart.web.app');
    expect(authDomainForHost('CHALAKCHARMART.COM'), 'chalakcharmart.com');
  });

  test('hosting channels use their own address', () {
    expect(authDomainForHost('chalakchar-mart--notif-5ntk6dge.web.app'), 'chalakchar-mart--notif-5ntk6dge.web.app');
    expect(authDomainForHost('chalakchar-mart--related-fen0n2pt.web.app'), 'chalakchar-mart--related-fen0n2pt.web.app');
  });

  test('anything else keeps the default', () {
    expect(authDomainForHost('localhost'), defaultAuthDomain);
    expect(authDomainForHost('evil.web.app'), defaultAuthDomain);
    expect(authDomainForHost('chalakchar-mart--x.web.app.evil.com'), defaultAuthDomain);
    expect(authDomainForHost(''), defaultAuthDomain);
  });
}
