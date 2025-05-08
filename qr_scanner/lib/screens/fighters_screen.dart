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
  String _searchText = '';

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
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('إضافة مقاتل', textDirection: TextDirection.rtl, style: TextStyle(color: Color(0xFF4D5D44))),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المقاتل',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.black87),
                      cursorColor: const Color(0xFF4D5D44),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.black87),
                      cursorColor: const Color(0xFF4D5D44),
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
                        labelText: 'القسم او الفوج',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
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
                              Icon(Icons.add, color: Color(0xFF4D5D44)),
                              SizedBox(width: 8),
                              Text('إضافة قسم جديد', style: TextStyle(color: Color(0xFF4D5D44))),
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
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('إضافة قسم جديد', style: TextStyle(color: Color(0xFF4D5D44))),
                              content: TextField(
                                controller: _newDepartmentController,
                                decoration: const InputDecoration(
                                  labelText: 'القسم',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                  labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                                  ),
                                ),
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.black87),
                                cursorColor: const Color(0xFF4D5D44),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('إلغاء', style: TextStyle(color: Color(0xFF4D5D44))),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4D5D44),
                                    foregroundColor: Colors.white,
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
                      style: const TextStyle(color: Colors.black87),
                      dropdownColor: Colors.white,
                      iconEnabledColor: const Color(0xFF4D5D44),
                    ),
                    const SizedBox(height: 16),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const Text('الحالة:', style: TextStyle(color: Color(0xFF4D5D44))),
                          const SizedBox(width: 8),
                          Text(_isActive ? 'فعال' : 'غير فعال', style: const TextStyle(color: Colors.black87)),
                          Switch(
                            value: _isActive,
                            activeColor: const Color(0xFF4D5D44),
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
                  child: const Text('إلغاء', style: TextStyle(color: Color(0xFF4D5D44))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4D5D44),
                    foregroundColor: Colors.white,
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Color(0xFF4D5D44), fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد أنك تريد حذف هذا المقاتل؟', style: TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Color(0xFF4D5D44))),
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
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF4D5D44),
          elevation: 1,
          title: const Text('المقاتلين', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF4D5D44),
          foregroundColor: Colors.white,
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
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF4D5D44),
                          const Color(0xFF627953),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4D5D44).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إجمالي المقاتلين', 
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              )
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$total', 
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 32, 
                                fontWeight: FontWeight.bold
                              )
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.groups, color: Colors.white, size: 40),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // Search Bar
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'بحث عن مقاتل...',
                    prefixIcon: Icon(Icons.search, color: const Color(0xFF4D5D44)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    hintStyle: TextStyle(color: Colors.grey[500]),
                  ),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  onChanged: (text) {
                    setState(() {
                      _searchText = text;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              // Fighters List
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Provider.of<DatabaseService>(context, listen: false).getAllFighters(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4D5D44)),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'خطأ: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 80,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا يوجد مقاتلين',
                              style: TextStyle(color: Colors.grey[500], fontSize: 18),
                            ),
                          ],
                        ),
                      );
                    }

                    final fighters = snapshot.data!;
                    // Filter fighters by search text
                    List<Map<String, dynamic>> filteredFighters = fighters;
                    if (_searchText.isNotEmpty) {
                      filteredFighters = fighters.where((fighter) {
                        return fighter['name'].toString().contains(_searchText) ||
                               fighter['number'].toString().contains(_searchText) ||
                               (fighter['department'] != null && fighter['department'].toString().contains(_searchText));
                      }).toList();
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        itemCount: filteredFighters.length,
                        itemBuilder: (context, index) {
                          final fighter = filteredFighters[index];
                          final isActive = fighter['status'] == DatabaseService.statusActive;
                          
                          return Container(
                            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showQRCode(fighter),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: isActive 
                                                ? [const Color(0xFF4D5D44), const Color(0xFF627953)]
                                                : [Colors.red.shade300, Colors.red.shade400],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isActive 
                                                  ? const Color(0xFF4D5D44).withOpacity(0.3)
                                                  : Colors.red.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            fighter['name'].substring(0, 1),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fighter['name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.phone, 
                                                  size: 14, 
                                                  color: Colors.grey[500],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  fighter['number'] ?? '-',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.badge, 
                                                  size: 14, 
                                                  color: Colors.grey[500],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  fighter['department'] ?? '-',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isActive 
                                                        ? const Color(0xFF4D5D44).withOpacity(0.1)
                                                        : Colors.red.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    isActive ? 'فعال' : 'غير فعال',
                                                    style: TextStyle(
                                                      color: isActive 
                                                          ? const Color(0xFF4D5D44)
                                                          : Colors.red,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4D5D44).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.qr_code, color: Color(0xFF4D5D44), size: 20),
                                            ),
                                            tooltip: 'عرض رمز QR',
                                            onPressed: () => _showQRCode(fighter),
                                          ),
                                          IconButton(
                                            icon: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4D5D44).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.edit, color: Color(0xFF4D5D44), size: 20),
                                            ),
                                            tooltip: 'تعديل بيانات المقاتل',
                                            onPressed: () => _showEditFighterDialog(fighter),
                                          ),
                                          IconButton(
                                            icon: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.delete, color: Colors.red, size: 20),
                                            ),
                                            tooltip: 'حذف المقاتل',
                                            onPressed: () => _confirmDeleteFighter(fighter),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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

  Future<void> _showQRCode(Map<String, dynamic> fighter) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'رمز QR للمقاتل: ${fighter['name']}',
          style: const TextStyle(color: Color(0xFF4D5D44)),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fighter['qr_image_path'] != null && fighter['qr_image_path'].isNotEmpty)
              Container(
                width: 250,
                height: 250,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Image.file(
                  File(fighter['qr_image_path']),
                  fit: BoxFit.contain,
                ),
              )
            else
              const Center(
                child: Text('QR صورة غير متاحة'),
              ),
            const SizedBox(height: 16),
            Text(
              'الاسم: ${fighter['name']}',
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            Text(
              'القسم: ${fighter['department'] ?? '-'}',
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Color(0xFF4D5D44))),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('طباعة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4D5D44),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _printSingleQRCode(fighter),
          ),
        ],
      ),
    );
  }

  Future<void> _printSingleQRCode(Map<String, dynamic> fighter) async {
    final qrPath = fighter['qr_image_path'] ?? '';
    if (qrPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مسار ملف QR غير متوفر')),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('معلومات ملف QR', style: TextStyle(color: Color(0xFF4D5D44))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تم حفظ رمز QR في المسار التالي:', style: TextStyle(color: Color(0xFF4D5D44))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Text(
                qrPath,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4D5D44),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                // Open the folder containing the QR code
                final dir = File(qrPath).parent.path;
                await Process.run('explorer.exe', [dir]);
              },
              label: const Text('فتح المجلد'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Color(0xFF4D5D44))),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditFighterDialog(Map<String, dynamic> fighter) async {
    _nameController.text = fighter['name'] ?? '';
    _numberController.text = fighter['number'] ?? '';
    _selectedDepartment = fighter['department'];
    _isActive = fighter['status'] == DatabaseService.statusActive;
    await _loadDepartments();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('تعديل بيانات المقاتل', textDirection: TextDirection.rtl, style: TextStyle(color: Color(0xFF4D5D44))),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المقاتل',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.black87),
                      cursorColor: const Color(0xFF4D5D44),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.black87),
                      cursorColor: const Color(0xFF4D5D44),
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
                        labelText: 'القسم او الفوج',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                        ),
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
                              Icon(Icons.add, color: Color(0xFF4D5D44)),
                              SizedBox(width: 8),
                              Text('إضافة قسم جديد', style: TextStyle(color: Color(0xFF4D5D44))),
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
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('إضافة قسم جديد', style: TextStyle(color: Color(0xFF4D5D44))),
                              content: TextField(
                                controller: _newDepartmentController,
                                decoration: const InputDecoration(
                                  labelText: 'القسم',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                  labelStyle: TextStyle(color: Color(0xFF4D5D44)),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFF4D5D44), width: 2),
                                  ),
                                ),
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.black87),
                                cursorColor: const Color(0xFF4D5D44),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('إلغاء', style: TextStyle(color: Color(0xFF4D5D44))),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4D5D44),
                                    foregroundColor: Colors.white,
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
                      style: const TextStyle(color: Colors.black87),
                      dropdownColor: Colors.white,
                      iconEnabledColor: const Color(0xFF4D5D44),
                    ),
                    const SizedBox(height: 16),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const Text('الحالة:', style: TextStyle(color: Color(0xFF4D5D44))),
                          const SizedBox(width: 8),
                          Text(_isActive ? 'فعال' : 'غير فعال', style: const TextStyle(color: Colors.black87)),
                          Switch(
                            value: _isActive,
                            activeColor: const Color(0xFF4D5D44),
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
                  child: const Text('إلغاء', style: TextStyle(color: Color(0xFF4D5D44))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4D5D44),
                    foregroundColor: Colors.white,
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
                      await databaseService.updateFighter({
                        'id': fighter['id'],
                        'name': _nameController.text,
                        'number': _numberController.text,
                        'department': _selectedDepartment,
                        'status': _isActive ? DatabaseService.statusActive : DatabaseService.statusInactive,
                      });
                      setState(() {});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تحديث بيانات المقاتل')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حدث خطأ: $e')),
                      );
                    }
                  },
                  child: const Text('حفظ التعديلات'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteFighter(Map<String, dynamic> fighter) async {
    final id = fighter['id'];
    if (id != null) {
      await _deleteFighter(id);
    }
  }
} 