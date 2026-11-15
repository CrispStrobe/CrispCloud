import 'dart:io';
Future<void> main() async {
 final url=Uri.parse('https://pub.dev/api/packages/args');
 final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
 client.findProxy=HttpClient.findProxyFromEnvironment;
 try { final request=await client.getUrl(url).timeout(const Duration(seconds:15)); final response=await request.close().timeout(const Duration(seconds:15)); print('HTTP ${response.statusCode}'); await response.drain(); } catch(e) { print(e); exitCode=1; } finally {client.close(force:true);}
}
