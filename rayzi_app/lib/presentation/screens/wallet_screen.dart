import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _balance;
  List<dynamic> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final balanceRes = await ApiService.get('/wallet/balance');
      final txRes = await ApiService.get('/wallet/transactions');
      setState(() {
        _balance = balanceRes.data['data'];
        _transactions = txRes.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Column(
                            children: [
                              Icon(Icons.monetization_on, color: Colors.amber, size: 32.w),
                              SizedBox(height: 8.h),
                              Text('${_balance?['coins'] ?? 0}',
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                              Text('Coins', style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Column(
                            children: [
                              Icon(Icons.diamond, color: Colors.cyan, size: 32.w),
                              SizedBox(height: 8.h),
                              Text('${_balance?['diamonds'] ?? 0}',
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                              Text('Diamonds', style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                Text('Transactions', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                ..._transactions.map((tx) => ListTile(
                  leading: Icon(
                    (tx['amount'] as num) >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    color: (tx['amount'] as num) >= 0 ? Colors.green : Colors.red,
                  ),
                  title: Text(tx['description'] ?? tx['type']),
                  subtitle: Text(DateFormat('MMM d, yyyy').format(DateTime.parse(tx['created_at']))),
                  trailing: Text('${tx['amount']} ${tx['currency']}'),
                )),
              ],
            ),
          ),
    );
  }
}
