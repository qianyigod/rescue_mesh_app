import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('开始测试服务器连接...');

  final endpoint = Uri.parse('http://101.35.52.133:3000/api/sos/sync');

  // 测试数据
  final testData = [
    {
      'id': 999,
      'senderMac': 'TEST_MAC',
      'latitude': 30.0,
      'longitude': 120.0,
      'bloodType': 'A',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'medicalProfile': {
        'name': 'Test User',
        'age': 25,
        'bloodTypeDetail': 'A',
        'medicalHistory': '',
        'allergies': '',
        'emergencyContact': '123456789',
      },
    },
  ];

  try {
    print('正在连接到服务器：$endpoint');
    final response = await http
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(testData),
        )
        .timeout(const Duration(seconds: 12));

    print('响应状态码：${response.statusCode}');
    print('响应内容：${response.body}');

    if (response.statusCode == 200) {
      print('✓ 测试成功！服务器正常接收数据');
    } else {
      print('✗ 服务器返回错误状态码：${response.statusCode}');
    }
  } catch (error) {
    print('✗ 连接失败：$error');
  }
}
