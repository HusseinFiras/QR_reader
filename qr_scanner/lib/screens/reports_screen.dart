import 'package:flutter/material.dart' hide Border;
import 'package:flutter/material.dart' as material show Border;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/rendering.dart' as ui;
import 'package:flutter/services.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final List<String> _reportTypes = ['يومي', 'أسبوعي', 'شهري'];
  final List<String> _fileTypes = ['Excel', 'PDF'];
  
  String _selectedReportType = 'يومي';
  String _selectedFileType = 'Excel';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isGenerating = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _updateDateRange();
  }

  void _updateDateRange() {
    final now = DateTime.now();
    
    switch (_selectedReportType) {
      case 'يومي':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = _startDate;
        break;
      case 'أسبوعي':
        // Get start of week (Saturday in Arabic calendar)
        final weekday = now.weekday;
        final daysToSubtract = (weekday + 1) % 7;
        _startDate = DateTime(now.year, now.month, now.day - daysToSubtract);
        _endDate = _startDate.add(const Duration(days: 6));
        break;
      case 'شهري':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0); // Last day of current month
        break;
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
        // Ensure end date is not before start date
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      
      // Format dates for query
      final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate.add(const Duration(days: 1)));
      
      // Get all fighters
      final fighters = await databaseService.getAllFighters();
      
      // Get attendance records for the date range
      final attendanceRecords = await databaseService.getAttendanceBetweenDates(startDateStr, endDateStr);
      
      // Show file save dialog
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'حدد مكان حفظ التقرير',
      );
      
      if (selectedDirectory == null) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'تم إلغاء عملية الحفظ';
        });
        return;
      }
      
      // Generate file name with timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final reportTypeStr = _selectedReportType.replaceAll(' ', '_');
      final dateRangeStr = '${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}';
      final fileName = 'تقرير_حضور_${reportTypeStr}_${dateRangeStr}_$timestamp';
      
      String filePath;
      
      if (_selectedFileType == 'Excel') {
        filePath = path.join(selectedDirectory, '$fileName.xlsx');
        await _generateExcelReport(filePath, fighters, attendanceRecords);
      } else {
        filePath = path.join(selectedDirectory, '$fileName.pdf');
        await _generatePdfReport(filePath, fighters, attendanceRecords);
      }
      
      setState(() {
        _isGenerating = false;
        _successMessage = 'تم إنشاء التقرير بنجاح وحفظه في:\n$filePath';
      });   
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'حدث خطأ أثناء إنشاء التقرير: $e';
      });
    }
  }

  Future<void> _generateExcelReport(String filePath, List<Map<String, dynamic>> fighters, List<Map<String, dynamic>> attendanceRecords) async {
    // Create Excel workbook
    final excel = xl.Excel.createExcel();
    
    // Remove default sheet
    excel.delete('Sheet1');
    
    // Create sheet for attendance summary
    final summarySheet = excel['ملخص_الحضور'];
    
    // Default styles
    final headerStyle = xl.CellStyle(
      bold: true,
      horizontalAlign: xl.HorizontalAlign.Right,
      verticalAlign: xl.VerticalAlign.Center,
      textWrapping: xl.TextWrapping.WrapText,
      rotation: 0,
      fontFamily: 'Arial',
      fontSize: 12,
    );
    
    final subHeaderStyle = xl.CellStyle(
      bold: true,
      horizontalAlign: xl.HorizontalAlign.Right,
      fontFamily: 'Arial',
      fontSize: 11,
    );
    
    final titleStyle = xl.CellStyle(
      bold: true,
      horizontalAlign: xl.HorizontalAlign.Right,
      fontFamily: 'Arial',
      fontSize: 16,
    );
    
    final dataStyle = xl.CellStyle(
      horizontalAlign: xl.HorizontalAlign.Right,
      fontFamily: 'Arial',
      fontSize: 10,
    );
    
    final numericStyle = xl.CellStyle(
      horizontalAlign: xl.HorizontalAlign.Center,
      fontFamily: 'Arial',
      fontSize: 10,
    );
    
    // Add header with styling
    final titleRow = 0;
    final titleCell = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: titleRow));
    titleCell.value = xl.TextCellValue('تقرير الحضور');
    titleCell.cellStyle = titleStyle;
    
    // Merge title cells for better appearance
    summarySheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: titleRow), 
                      xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: titleRow));
    
    // Add date range info
    final dateRange = '${DateFormat('yyyy-MM-dd').format(_startDate)} إلى ${DateFormat('yyyy-MM-dd').format(_endDate)}';
    final dateRangeRow = 1;
    final dateRangeCell = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: dateRangeRow));
    dateRangeCell.value = xl.TextCellValue('الفترة: $dateRange');
    dateRangeCell.cellStyle = subHeaderStyle;
    
    // Merge date range cells
    summarySheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: dateRangeRow), 
                      xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: dateRangeRow));
    
    // Add report type info
    final typeRow = 2;
    final typeCell = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: typeRow));
    typeCell.value = xl.TextCellValue('النوع: $_selectedReportType');
    typeCell.cellStyle = subHeaderStyle;
    
    // Merge type cells
    summarySheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: typeRow), 
                      xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: typeRow));
    
    // Add empty row for spacing
    final emptyRow = 3;
    
    // Add column headers
    final headerRow = 4;
    
    final headers = [
      'رقم المقاتل',
      'الاسم',
      'القسم',
      'عدد أيام الحضور',
      'عدد أيام الغياب',
      'عدد مرات التأخير'
    ];
    
    for (int i = 0; i < headers.length; i++) {
      final cell = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }
    
    // Group attendance by fighter
    final Map<int, Map<String, dynamic>> fighterAttendance = {};
    
    // Initialize with all fighters
    for (final fighter in fighters) {
      final fighterId = fighter[DatabaseService.columnId] as int;
      fighterAttendance[fighterId] = {
        'fighter': fighter,
        'daysPresent': 0,
        'daysAbsent': 0,
        'lateCount': 0,
        'attendanceByDate': <String, List<Map<String, dynamic>>>{},
      };
    }
    
    // Calculate days between start and end date
    final daysBetween = _endDate.difference(_startDate).inDays + 1;
    
    // Process attendance records
    for (final record in attendanceRecords) {
      final fighterId = record[DatabaseService.columnFighterId] as int;
      final timestamp = record[DatabaseService.columnTimestamp] as String;
      final date = timestamp.split(' ')[0];
      final time = timestamp.split(' ')[1];
      
      if (!fighterAttendance.containsKey(fighterId)) continue;
      
      // Initialize attendance for this date if not exists
      if (!fighterAttendance[fighterId]!['attendanceByDate'].containsKey(date)) {
        fighterAttendance[fighterId]!['attendanceByDate'][date] = [];
      }
      
      // Add record to this date
      fighterAttendance[fighterId]!['attendanceByDate'][date]!.add(record);
      
      // Check if check-in record and if it's late
      if (record[DatabaseService.columnType] == DatabaseService.typeCheckIn) {
        final recordTime = DateFormat('HH:mm').parse(time);
        final lateThreshold = DateFormat('HH:mm').parse('09:30');
        
        if (recordTime.isAfter(lateThreshold)) {
          fighterAttendance[fighterId]!['lateCount'] = (fighterAttendance[fighterId]!['lateCount'] as int) + 1;
        }
      }
    }
    
    // Calculate days present and absent
    for (final attendance in fighterAttendance.values) {
      final daysPresent = attendance['attendanceByDate'].length;
      attendance['daysPresent'] = daysPresent;
      attendance['daysAbsent'] = daysBetween - daysPresent;
    }
    
    // Add data rows
    int row = headerRow + 1;
    
    // Apply alternating row colors for better readability
    var rowColor = false;
    
    for (final attendance in fighterAttendance.values) {
      final fighter = attendance['fighter'] as Map<String, dynamic>;
      
      // Create row styles
      final currentRowStyle = dataStyle;
      final currentNumericStyle = numericStyle;
      
      // Fighter number
      final cell1 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      cell1.value = xl.TextCellValue(fighter[DatabaseService.columnNumber] ?? '');
      cell1.cellStyle = currentRowStyle;
      
      // Fighter name
      final cell2 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
      cell2.value = xl.TextCellValue(fighter[DatabaseService.columnName] ?? '');
      cell2.cellStyle = currentRowStyle;
      
      // Department
      final cell3 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
      cell3.value = xl.TextCellValue(fighter[DatabaseService.columnDepartment] ?? '');
      cell3.cellStyle = currentRowStyle;
      
      // Days present
      final cell4 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
      cell4.value = xl.IntCellValue(attendance['daysPresent']);
      cell4.cellStyle = currentNumericStyle;
      
      // Days absent
      final cell5 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
      cell5.value = xl.IntCellValue(attendance['daysAbsent']);
      cell5.cellStyle = currentNumericStyle;
      
      // Late count
      final cell6 = summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
      cell6.value = xl.IntCellValue(attendance['lateCount']);
      cell6.cellStyle = currentNumericStyle;
      
      row++;
    }
    
    // Add detail sheet
    final detailSheet = excel['تفاصيل_الحضور'];
    
    // Add header with styling for detail sheet
    final detailTitleRow = 0;
    final detailTitleCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: detailTitleRow));
    detailTitleCell.value = xl.TextCellValue('تفاصيل سجلات الحضور');
    detailTitleCell.cellStyle = titleStyle;
    
    // Merge title cells
    detailSheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: detailTitleRow), 
                     xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: detailTitleRow));
    
    // Add date range info to detail sheet
    final detailDateRangeRow = 1;
    final detailDateRangeCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: detailDateRangeRow));
    detailDateRangeCell.value = xl.TextCellValue('الفترة: $dateRange');
    detailDateRangeCell.cellStyle = subHeaderStyle;
    
    // Merge date range cells in detail sheet
    detailSheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: detailDateRangeRow), 
                     xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: detailDateRangeRow));
    
    // Add empty row
    
    // Add detail column headers
    final detailHeaderRow = 3;
    
    final detailHeaders = [
      'التاريخ',
      'الوقت',
      'رقم المقاتل',
      'الاسم',
      'القسم',
      'نوع التسجيل',
      'ملاحظات'
    ];
    
    for (int i = 0; i < detailHeaders.length; i++) {
      final cell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: detailHeaderRow));
      cell.value = xl.TextCellValue(detailHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    
    // Add detailed data rows
    row = detailHeaderRow + 1;
    rowColor = false;
    
    for (final record in attendanceRecords) {
      final timestamp = record[DatabaseService.columnTimestamp] as String;
      final parts = timestamp.split(' ');
      final date = parts[0];
      final time = parts[1];
      
      final fighterId = record[DatabaseService.columnFighterId] as int;
      final fighter = fighters.firstWhere(
        (f) => f[DatabaseService.columnId] == fighterId, 
        orElse: () => {'name': 'غير معروف', 'number': '', 'department': ''}
      );
      
      // Create row styles
      final currentRowStyle = dataStyle;
      final currentCenterStyle = xl.CellStyle(
        horizontalAlign: xl.HorizontalAlign.Center,
        fontFamily: 'Arial',
        fontSize: 10,
      );
      
      // Date
      final dateCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      dateCell.value = xl.TextCellValue(date);
      dateCell.cellStyle = currentCenterStyle;
      
      // Time
      final timeCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
      timeCell.value = xl.TextCellValue(time);
      timeCell.cellStyle = currentCenterStyle;
      
      // Fighter number
      final numberCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
      numberCell.value = xl.TextCellValue(fighter[DatabaseService.columnNumber] ?? '');
      numberCell.cellStyle = currentRowStyle;
      
      // Fighter name
      final nameCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
      nameCell.value = xl.TextCellValue(fighter[DatabaseService.columnName] ?? '');
      nameCell.cellStyle = currentRowStyle;
      
      // Department
      final deptCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
      deptCell.value = xl.TextCellValue(fighter[DatabaseService.columnDepartment] ?? '');
      deptCell.cellStyle = currentRowStyle;
      
      // Record type
      final typeCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
      typeCell.value = xl.TextCellValue(
        record[DatabaseService.columnType] == DatabaseService.typeCheckIn ? 'حضور' : 'انصراف'
      );
      typeCell.cellStyle = currentCenterStyle;
      
      // Notes
      final notesCell = detailSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
      notesCell.value = xl.TextCellValue(record[DatabaseService.columnNotes] ?? '');
      notesCell.cellStyle = currentRowStyle;
      
      row++;
    }
    
    // Set RTL direction for all cells and add borders
    for (final sheet in excel.sheets.values) {
      for (int r = 0; r < sheet.maxRows; r++) {
        for (int c = 0; c < sheet.maxColumns; c++) {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          if (cell.value != null) {
            cell.cellStyle = xl.CellStyle(
              fontFamily: 'Arial',
              leftBorder: xl.Border(borderStyle: xl.BorderStyle.Thin),
              rightBorder: xl.Border(borderStyle: xl.BorderStyle.Thin),
              topBorder: xl.Border(borderStyle: xl.BorderStyle.Thin),
              bottomBorder: xl.Border(borderStyle: xl.BorderStyle.Thin),
            );
          }
        }
      }
    }
    
    // Save the Excel file
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
  }

  Future<void> _generatePdfReport(String filePath, List<Map<String, dynamic>> fighters, List<Map<String, dynamic>> attendanceRecords) async {
    try {
      // Load the font files - This is critical for Arabic text support
      final arabicFontData = await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf');
      final boldArabicFontData = await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf');
      
      // Create PDF document
      final pdf = pw.Document();

      // Register fonts
      final arabicFont = pw.Font.ttf(arabicFontData);
      final boldArabicFont = pw.Font.ttf(boldArabicFontData);
      
      // Setup theme with Arabic font
      final myTheme = pw.ThemeData.withFont(
        base: arabicFont,
        bold: boldArabicFont,
      );
      
      // Group attendance by fighter (same logic as Excel report)
      final Map<int, Map<String, dynamic>> fighterAttendance = {};
      
      for (final fighter in fighters) {
        final fighterId = fighter[DatabaseService.columnId] as int;
        fighterAttendance[fighterId] = {
          'fighter': fighter,
          'daysPresent': 0,
          'daysAbsent': 0,
          'lateCount': 0,
          'attendanceByDate': <String, List<Map<String, dynamic>>>{},
        };
      }
      
      final daysBetween = _endDate.difference(_startDate).inDays + 1;
      
      for (final record in attendanceRecords) {
        final fighterId = record[DatabaseService.columnFighterId] as int;
        final timestamp = record[DatabaseService.columnTimestamp] as String;
        final date = timestamp.split(' ')[0];
        final time = timestamp.split(' ')[1];
        
        if (!fighterAttendance.containsKey(fighterId)) continue;
        
        if (!fighterAttendance[fighterId]!['attendanceByDate'].containsKey(date)) {
          fighterAttendance[fighterId]!['attendanceByDate'][date] = [];
        }
        
        fighterAttendance[fighterId]!['attendanceByDate'][date]!.add(record);
        
        if (record[DatabaseService.columnType] == DatabaseService.typeCheckIn) {
          final recordTime = DateFormat('HH:mm').parse(time);
          final lateThreshold = DateFormat('HH:mm').parse('09:30');
          
          if (recordTime.isAfter(lateThreshold)) {
            fighterAttendance[fighterId]!['lateCount'] = (fighterAttendance[fighterId]!['lateCount'] as int) + 1;
          }
        }
      }
      
      for (final attendance in fighterAttendance.values) {
        final daysPresent = attendance['attendanceByDate'].length;
        attendance['daysPresent'] = daysPresent;
        attendance['daysAbsent'] = daysBetween - daysPresent;
      }
      
      // Define date range string
      final dateRange = '${DateFormat('yyyy-MM-dd').format(_startDate)} إلى ${DateFormat('yyyy-MM-dd').format(_endDate)}';
      
      // Create summary page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: myTheme,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text('تقرير الحضور', 
                        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('الفترة: $dateRange'),
                        pw.Text('النوع: $_selectedReportType'),
                      ],
                    ),
                    pw.SizedBox(height: 30),
                    pw.Table(
                      border: pw.TableBorder.all(width: 1),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(4),
                        2: const pw.FlexColumnWidth(3),
                        3: const pw.FlexColumnWidth(2),
                        4: const pw.FlexColumnWidth(2),
                        5: const pw.FlexColumnWidth(2),
                      },
                      children: [
                        // Header row
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('رقم المقاتل', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold), 
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('الاسم', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('القسم', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('أيام الحضور', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('أيام الغياب', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('مرات التأخير', 
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.center
                              ),
                            ),
                          ],
                        ),
                        // Data rows
                        ...fighterAttendance.values.map((attendance) {
                          final fighter = attendance['fighter'] as Map<String, dynamic>;
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(fighter[DatabaseService.columnNumber] ?? ''),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(fighter[DatabaseService.columnName] ?? ''),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(fighter[DatabaseService.columnDepartment] ?? ''),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(attendance['daysPresent'].toString(),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(attendance['daysAbsent'].toString(),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(attendance['lateCount'].toString(),
                                  textAlign: pw.TextAlign.center),
                              ),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      
      // Create detailed records page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: myTheme,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text('تفاصيل سجلات الحضور', 
                        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text('الفترة: $dateRange'),
                    pw.SizedBox(height: 30),
                    pw.Expanded(
                      child: pw.Table(
                        border: pw.TableBorder.all(width: 1),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2),
                          1: const pw.FlexColumnWidth(2),
                          2: const pw.FlexColumnWidth(3),
                          3: const pw.FlexColumnWidth(4),
                          4: const pw.FlexColumnWidth(2),
                        },
                        children: [
                          // Header row
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('التاريخ', 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('الوقت', 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('رقم المقاتل', 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('الاسم', 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('نوع التسجيل', 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                              ),
                            ],
                          ),
                          // Only show first 30 records to avoid overflow
                          ...attendanceRecords.take(30).map((record) {
                            final timestamp = record[DatabaseService.columnTimestamp] as String;
                            final parts = timestamp.split(' ');
                            final date = parts[0];
                            final time = parts[1];
                            
                            final fighterId = record[DatabaseService.columnFighterId] as int;
                            final fighter = fighters.firstWhere(
                              (f) => f[DatabaseService.columnId] == fighterId, 
                              orElse: () => {'name': 'غير معروف', 'number': ''}
                            );
                            
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(date),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(time, textAlign: pw.TextAlign.center),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(fighter[DatabaseService.columnNumber] ?? ''),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(fighter[DatabaseService.columnName] ?? ''),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    record[DatabaseService.columnType] == DatabaseService.typeCheckIn 
                                      ? 'حضور' 
                                      : 'انصراف',
                                    textAlign: pw.TextAlign.center
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    if (attendanceRecords.length > 30)
                      pw.Text('* التقرير يعرض أول 30 سجل فقط. للاطلاع على كافة السجلات، يرجى تصدير التقرير بصيغة Excel.'),
                  ],
                ),
              ),
            );
          },
        ),
      );
      
      // Save the PDF file
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
    } catch (e) {
      print("PDF generation error: $e");
      rethrow;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF4D5D44),
          elevation: 1,
          title: const Text(
            'التقارير',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Report Configuration Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: material.Border.all(color: const Color(0xFFE0E0E0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إعدادات التقرير',
                      style: TextStyle(
                        color: Color(0xFF4D5D44),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Report Type Selector
                    Row(
                      children: [
                        const Expanded(
                          flex: 1,
                          child: Text(
                            'نوع التقرير:',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Wrap(
                            spacing: 16,
                            children: _reportTypes.map((type) {
                              return ChoiceChip(
                                label: Text(type),
                                selected: _selectedReportType == type,
                                selectedColor: const Color(0xFF4D5D44),
                                labelStyle: TextStyle(
                                  color: _selectedReportType == type ? Colors.white : Colors.black87,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedReportType = type;
                                      _updateDateRange();
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Date Range Selector
                    Row(
                      children: [
                        const Expanded(
                          flex: 1,
                          child: Text(
                            'الفترة الزمنية:',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectStartDate(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: material.Border.all(color: const Color(0xFFE0E0E0)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          DateFormat('yyyy-MM-dd').format(_startDate),
                                          style: const TextStyle(color: Colors.black87),
                                        ),
                                        const Icon(Icons.calendar_today, color: Color(0xFF4D5D44), size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text('إلى', style: TextStyle(color: Colors.black87)),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectEndDate(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: material.Border.all(color: const Color(0xFFE0E0E0)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          DateFormat('yyyy-MM-dd').format(_endDate),
                                          style: const TextStyle(color: Colors.black87),
                                        ),
                                        const Icon(Icons.calendar_today, color: Color(0xFF4D5D44), size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // File Type Selector
                    Row(
                      children: [
                        const Expanded(
                          flex: 1,
                          child: Text(
                            'نوع الملف:',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Wrap(
                            spacing: 16,
                            children: _fileTypes.map((type) {
                              return ChoiceChip(
                                label: Text(type),
                                selected: _selectedFileType == type,
                                selectedColor: const Color(0xFF4D5D44),
                                labelStyle: TextStyle(
                                  color: _selectedFileType == type ? Colors.white : Colors.black87,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedFileType = type;
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Generate Button
                    Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.file_download),
                        label: const Text('إنشاء التقرير'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4D5D44),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        onPressed: _isGenerating ? null : _generateReport,
                      ),
                    ),
                    
                    // Status messages
                    if (_isGenerating)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4D5D44)),
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'جاري إنشاء التقرير...',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: material.Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.red),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: material.Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: const TextStyle(color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Help Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.help, color: Color(0xFF4D5D44)),
                        const SizedBox(width: 8),
                        Text(
                          'مساعدة',
                          style: TextStyle(
                            color: const Color(0xFF4D5D44),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '- التقرير اليومي يعرض سجلات الحضور لليوم المحدد فقط.\n'
                      '- التقرير الأسبوعي يعرض سجلات الحضور للأسبوع الذي يبدأ من التاريخ المحدد.\n'
                      '- التقرير الشهري يعرض سجلات الحضور للشهر الكامل الذي يبدأ من التاريخ المحدد.\n'
                      '- يمكنك اختيار تاريخ البداية والنهاية يدويًا لتخصيص نطاق التقرير.\n'
                      '- اختر نوع الملف (Excel أو PDF) حسب احتياجاتك.',
                      style: TextStyle(
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 