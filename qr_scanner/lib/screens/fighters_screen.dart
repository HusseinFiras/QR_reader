import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/qr_service.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class FightersScreen extends StatefulWidget {
  const FightersScreen({Key? key}) : super(key: key);

  @override
  State<FightersScreen> createState() => _FightersScreenState();
}

class _FightersScreenState extends State<FightersScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  String? _selectedDepartment;
  final TextEditingController _newDepartmentController = TextEditingController();
  bool _isActive = true;
  List<String> _departments = [];

  Future<void> _loadDepartments() async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final departments = await databaseService.getAllDepartments();
    setState(() {
      _departments = departments;
    });
  }

  Future<void> _showAddFighterDialog() async {
    _nameController.clear();
    _numberController.clear();
    _selectedDepartment = null;
    _isActive = true;
    await _loadDepartments();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF23262B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('إضافة مقاتل', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'الاسم',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: 'الرقم',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedDepartment,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'القسم',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      items: [
                        ..._departments.map((dep) => DropdownMenuItem(
                              value: dep,
                              child: Text(dep, textDirection: TextDirection.rtl, textAlign: TextAlign.right),
                            )),
                        DropdownMenuItem(
                          value: '__add_new__',
                          child: Row(
                            children: const [
                              Icon(Icons.add, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('إضافة قسم جديد', style: TextStyle(color: Colors.blue)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) async {
                        if (val == '__add_new__') {
                          _newDepartmentController.clear();
                          final newDep = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF23262B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('إضافة قسم جديد', style: TextStyle(color: Colors.white)),
                              content: TextField(
                                controller: _newDepartmentController,
                                decoration: const InputDecoration(
                                  labelText: 'القسم',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF90B4FF),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context, _newDepartmentController.text.trim());
                                  },
                                  child: const Text('إضافة'),
                                ),
                              ],
                            ),
                          );
                          if (newDep != null && newDep.isNotEmpty) {
                            final databaseService = Provider.of<DatabaseService>(context, listen: false);
                            await databaseService.insertDepartment(newDep);
                            await _loadDepartments();
                            setStateDialog(() {
                              _selectedDepartment = newDep;
                            });
                          }
                        } else {
                          setStateDialog(() {
                            _selectedDepartment = val;
                          });
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      dropdownColor: const Color(0xFF23262B),
                      iconEnabledColor: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const Text('الحالة:', style: TextStyle(color: Colors.white)),
                          const SizedBox(width: 8),
                          Text(_isActive ? 'فعال' : 'غير فعال', style: const TextStyle(color: Colors.white)),
                          Switch(
                            value: _isActive,
                            activeColor: Colors.green,
                            inactiveThumbColor: Colors.red,
                            onChanged: (val) {
                              setStateDialog(() {
                                _isActive = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF90B4FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (_nameController.text.isEmpty || _numberController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الرجاء إدخال الاسم والرقم')),
                      );
                      return;
                    }
                    if (_numberController.text.length != 11) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الرقم غير صحيح يجب أن يكون 11 رقماً')),
                      );
                      return;
                    }
                    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الرجاء اختيار القسم')),
                      );
                      return;
                    }
                    try {
                      final databaseService = Provider.of<DatabaseService>(context, listen: false);
                      final fighterId = await databaseService.insertFighter({
                        'name': _nameController.text,
                        'number': _numberController.text,
                        'department': _selectedDepartment,
                        'qr_code': '',
                        'qr_image_path': '',
                        'status': _isActive ? DatabaseService.statusActive : DatabaseService.statusInactive,
                      });
                      
                      // Generate and save QR code
                      final qrService = QRService();
                      final qrImagePath = await qrService.generateAndSaveQRCode(fighterId.toString(), _nameController.text);
                      
                      // Update fighter with QR code information
                      await databaseService.updateFighter({
                        'id': fighterId,
                        'qr_code': fighterId.toString(),
                        'qr_image_path': qrImagePath,
                      });
                      
                      setState(() {});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إضافة المقاتل بنجاح')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حدث خطأ: $e')),
                      );
                    }
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteFighter(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF23262B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد أنك تريد حذف هذا المقاتل؟', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final fighter = await databaseService.getFighter(id);
      if (fighter != null) {
        // Delete QR code image
        final qrService = QRService();
        await qrService.deleteQRCode(fighter['name']);
        // Delete fighter from database
        await databaseService.deleteFighter(id);
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المقاتل')));
    }
  }

  Future<void> _toggleFighterStatus(int id, String currentStatus) async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final newStatus = currentStatus == DatabaseService.statusActive
        ? DatabaseService.statusInactive
        : DatabaseService.statusActive;
    await databaseService.updateFighterStatus(id, newStatus);
    setState(() {});
  }

  Future<void> _showQRCodeDialog(String fighterId, String fighterName, String qrImagePath) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF23262B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('رمز ال QR للمقاتل : $fighterName', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(
              File(qrImagePath),
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF90B4FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                // Copy QR code path to clipboard
                await Clipboard.setData(ClipboardData(text: qrImagePath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ مسار ملف QR')),
                );
              },
              child: const Text('نسخ مسار الملف'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF181B20),
        appBar: AppBar(
          backgroundColor: const Color(0xFF181B20),
          elevation: 0,
          title: const Text('المقاتلين', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF90B4FF),
          foregroundColor: Colors.black,
          onPressed: _showAddFighterDialog,
          child: const Icon(Icons.person_add),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary Card
              FutureBuilder<List<Map<String, dynamic>>>(
                future: Provider.of<DatabaseService>(context, listen: false).getAllFighters(),
                builder: (context, snapshot) {
                  final total = snapshot.data?.length ?? 0;
                  return Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF23262B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('إجمالي المقاتلين', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  Text('$total', style: const TextStyle(color: Color(0xFF90B4FF), fontSize: 32, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Icon(Icons.groups, color: Color(0xFF90B4FF), size: 40),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              // Fighters List
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Provider.of<DatabaseService>(context, listen: false).getAllFighters(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('حدث خطأ: ${snapshot.error}', style: TextStyle(color: Colors.white)));
                    }
                    final fighters = snapshot.data ?? [];
                    if (fighters.isEmpty) {
                      return const Center(child: Text('لا يوجد مقاتلين', style: TextStyle(color: Colors.white70)));
                    }
                    return ListView.separated(
                      itemCount: fighters.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final fighter = fighters[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF23262B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF90B4FF),
                                child: const Icon(Icons.person, color: Colors.black),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fighter['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('الرقم: ${fighter['number']}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                    if ((fighter['department'] ?? '').toString().isNotEmpty)
                                      Text('القسم: ${fighter['department']}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              // QR Code button
                              IconButton(
                                icon: const Icon(Icons.qr_code, color: Color(0xFF90B4FF)),
                                tooltip: 'عرض رمز QR',
                                onPressed: () => _showQRCodeDialog(
                                  fighter['id'].toString(),
                                  fighter['name'],
                                  fighter['qr_image_path'],
                                ),
                              ),
                              // Status Switch
                              Column(
                                children: [
                                  Text(fighter['status'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  Switch(
                                    value: fighter['status'] == DatabaseService.statusActive,
                                    activeColor: Colors.green,
                                    inactiveThumbColor: Colors.red,
                                    onChanged: (val) => _toggleFighterStatus(fighter['id'], fighter['status']),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              // Delete button
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'حذف',
                                onPressed: () => _deleteFighter(fighter['id']),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 