import 'package:flutter/material.dart';
import '../services/google_sheets_service.dart';
import 'google_sheets_sheet.dart';

class UserProfileAvatar extends StatelessWidget {
  const UserProfileAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GoogleSheetsService.instance,
      builder: (context, _) {
        final service = GoogleSheetsService.instance;
        final isConnected = service.isConnected;
        final photoUrl = service.userPhotoUrl;
        final name = service.userName;
        final email = service.userEmail;

        String initial = 'G';
        if (name.trim().isNotEmpty) {
          initial = name.trim()[0].toUpperCase();
        } else if (email.trim().isNotEmpty) {
          initial = email.trim()[0].toUpperCase();
        }

        Widget avatar;
        if (isConnected && photoUrl.isNotEmpty) {
          avatar = CircleAvatar(
            radius: 16,
            backgroundColor: Colors.green.shade800,
            child: ClipOval(
              child: Image.network(
                photoUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) {
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        } else if (isConnected) {
          avatar = CircleAvatar(
            radius: 16,
            backgroundColor: Colors.green.shade800,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else {
          avatar = CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.account_circle,
              size: 28,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tooltip(
            message: isConnected ? 'Google Account: $email' : 'Connect Google Account',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => GoogleSheetsSheet.show(context),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: avatar,
                  ),
                  if (isConnected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.shade700,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).appBarTheme.backgroundColor ??
                              Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
