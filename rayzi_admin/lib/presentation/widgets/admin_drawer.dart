import 'package:flutter/material.dart';
import '../../services/admin_api.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rayzi Admin', style: TextStyle(color: Colors.white, fontSize: 24)),
                Text('Management Panel', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pushNamed(context, '/dashboard'),
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Users'),
            onTap: () => Navigator.pushNamed(context, '/users'),
          ),
          ListTile(
            leading: const Icon(Icons.live_tv),
            title: const Text('Streams'),
            onTap: () => Navigator.pushNamed(context, '/streams'),
          ),
          ListTile(
            leading: const Icon(Icons.report),
            title: const Text('Reports'),
            onTap: () => Navigator.pushNamed(context, '/reports'),
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: const Text('Gifts'),
            onTap: () => Navigator.pushNamed(context, '/gifts'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Withdrawals'),
            onTap: () => Navigator.pushNamed(context, '/withdrawals'),
          ),
          ListTile(
            leading: const Icon(Icons.storefront),
            title: const Text('Expansion'),
            subtitle: const Text('Shop · Recharges · Host apps'),
            onTap: () => Navigator.pushNamed(context, '/expansion'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance),
            title: const Text('Wallet Economy'),
            subtitle: const Text('Ledger · Adjustments · Withdraw queue'),
            onTap: () => Navigator.pushNamed(context, '/wallet-economy'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AdminApi.logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              }
            },
          ),
        ],
      ),
    );
  }
}
