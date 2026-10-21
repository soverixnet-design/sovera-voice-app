import 'firebase_room_session.dart';
// Separate sign-in verification target. Legacy room/wallet APIs are not invoked.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'firebase_profile.dart';
import 'firebase_broadcasts.dart';
import 'app_preferences.dart';
import 'firebase_rooms.dart';
import 'firebase_greedy_wheel.dart';
import 'firebase_sovera_home.dart';
import 'sovera_visuals.dart' show BrandLogo;

const _webClient = '486331346860-trjijmpedgurb05npsvao3d3v327b6ii.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoveraPreferences.load();
  try {
    await Firebase.initializeApp(options: const FirebaseOptions(
      apiKey: 'AIzaSyB_VFxK6IXwvPtm84LV6kojh1s_zsQN-Wg',
      appId: '1:486331346860:android:40c135895f2ab81a315409',
      messagingSenderId: '486331346860',
      projectId: 'sovera-app-7d1d6',
      storageBucket: 'sovera-app-7d1d6.firebasestorage.app',
    ));
    runApp(const FirebaseLoginApp());
  } catch (_) {
    runApp(const MaterialApp(home: Scaffold(body: Center(
      child: Text('Sign-in could not start. Close Sovera and try again.'),
    ))));
  }
}

String firebaseLoginError(String code) => switch (code) {
  'invalid-credential' || 'wrong-password' || 'user-not-found' =>
    'The email or Sovera password is incorrect.',
  'email-already-in-use' => 'An account already uses this email. Sign in instead.',
  'invalid-email' => 'Enter a valid email address.',
  'weak-password' => 'Choose a password with at least 8 characters.',
  'too-many-requests' => 'Too many attempts. Please wait before trying again.',
  'network-request-failed' => 'Could not connect. Check your internet and retry.',
  'user-disabled' => 'This account is disabled. Contact support.',
  'operation-not-allowed' => 'This sign-in method is unavailable. Try the other method.',
  'account-exists-with-different-credential' =>
    'Use the sign-in method you originally used for this email.',
  _ => 'Sign-in did not complete. Please retry.',
};

class FirebaseLoginApp extends StatelessWidget {
  const FirebaseLoginApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sovera Voice Chat', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF12172D),
      colorScheme: const ColorScheme.dark(primary: Color(0xFF9268F4)),
    ),
    builder:(context,child)=>StreamBuilder<User?>(stream:FirebaseAuth.instance.userChanges(),builder:(context,snapshot){
      final user=snapshot.data;
      return user==null?child??const SizedBox():_CelebrationSession(key:ValueKey(user.uid),user:user,child:child??const SizedBox());
    }),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('Could not restore sign-in. Please restart.')));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == null ? const FirebaseLoginPage() : FirebaseSoveraHome(key:ValueKey(snapshot.data!.uid),user: snapshot.data!);
      },
    ),
  );
}

class FirebaseLoginPage extends StatefulWidget {
  const FirebaseLoginPage({super.key});
  @override
  State<FirebaseLoginPage> createState() => _FirebaseLoginPageState();
}

class _FirebaseLoginPageState extends State<FirebaseLoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool create = false, busy = false;
  String? message;
  Future<void>? googleInitialization;

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> perform(Future<String?> Function() action,{bool googleFlow=false}) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try {
      final result = await action();
      if (mounted) setState(() => message = result);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = googleFlow
        ? 'Google account sign-in failed at Firebase (${e.code}). Check the Android signing certificate and Google provider settings.'
        : firebaseLoginError(e.code));
    } on GoogleSignInException catch (e) {
      if (mounted) setState(() => message = e.code == GoogleSignInExceptionCode.canceled
        ? 'Google sign-in was cancelled.' : 'Google sign-in failed (${e.code.name}). Check the app signing SHA-1 in Firebase. Email sign-in is also available.');
    } catch (_) {
      if (mounted) setState(() => message = 'Could not connect. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> google() => perform(() async {
    final signIn = GoogleSignIn.instance;
    googleInitialization ??= signIn.initialize(serverClientId: _webClient);
    try { await googleInitialization; } catch (_) { googleInitialization = null; rethrow; }
    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw FirebaseAuthException(code: 'invalid-credential');
    await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    return null;
  },googleFlow:true);

  bool validEmail() => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim());
  Future<void> submit() async {
    if (!validEmail() || password.text.isEmpty || (create && password.text.length < 8)) {
      setState(() => message = 'Enter your email and a Sovera password${create ? ' of at least 8 characters' : ''}.');
      return;
    }
    await perform(() async {
      if (create) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(), password: password.text,
        );
        await credential.user?.sendEmailVerification();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      }
      return null;
    });
  }

  Future<void> reset() async {
    if (!validEmail()) { setState(() => message = 'Enter your email address first.'); return; }
    await perform(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      return 'If this email has an account, a password reset email will arrive shortly.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Container(
    decoration: const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF882580),Color(0xFF43249A),Color(0xFF25116B)])),
    child: SafeArea(child: Center(
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420), child: AutofillGroup(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BrandLogo(size:130),
          const SizedBox(height: 20),
          const Text('Welcome to Sovera', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Your voice. Your world.', textAlign: TextAlign.center,style:TextStyle(color:Colors.white70)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: busy ? null : google, icon: const Icon(Icons.login), label: const Text('Continue with Google')),
          const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('or use email', textAlign: TextAlign.center)),
          TextField(controller: email, enabled: !busy, keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email], autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email address')),
          const SizedBox(height: 14),
          TextField(controller: password, enabled: !busy, obscureText: true, autocorrect: false,
            enableSuggestions: false, autofillHints: [create ? AutofillHints.newPassword : AutofillHints.password],
            onSubmitted: (_) => submit(), decoration: const InputDecoration(labelText: 'Sovera password')),
          const SizedBox(height: 18),
          if (message != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(message!)),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : create ? 'Create account' : 'Sign in with email')),
          if (!create) TextButton(onPressed: busy ? null : reset, child: const Text('Forgot password?')),
          TextButton(onPressed: busy ? null : () => setState(() { create = !create; password.clear(); message = null; }),
            child: Text(create ? 'Already registered? Sign in' : 'New to Sovera? Create an email account')),
          const Text('Use a Sovera account password for email sign-in. You never need to share your Google password with Sovera.',
            style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      )),
    )),
  ))));
}

class FirebaseSignedInPage extends StatefulWidget {
  final User user;
  const FirebaseSignedInPage({super.key, required this.user});
  @override
  State<FirebaseSignedInPage> createState() => _FirebaseSignedInPageState();
}

class _FirebaseSignedInPageState extends State<FirebaseSignedInPage> {
  final profileClient = http.Client();
  late final profileApi = FirebaseProfileApi(uid:widget.user.uid,
    token:() async => FirebaseAuth.instance.currentUser?.uid==widget.user.uid ? widget.user.getIdToken() : null, client:profileClient);
  @override void dispose() { profileClient.close(); super.dispose(); }
  bool busy = false;
  String? message;
  Future<void> action(Future<void> Function() task) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { await task(); }
    on FirebaseAuthException catch (e) { if (mounted) setState(() => message = firebaseLoginError(e.code)); }
    catch (_) { if (mounted) setState(() => message = 'Could not complete the request. Please retry.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Sovera account')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.verified_user_outlined, size: 64, color: Colors.greenAccent),
      const SizedBox(height: 20),
      const Text('Sign-in successful', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text(widget.user.displayName ?? 'Sovera user'),
      Text(widget.user.email ?? ''),
      const SizedBox(height: 20),
      Text(widget.user.emailVerified ? 'Email verified' : 'Please verify your email address.'),
      if (!widget.user.emailVerified) ...[
        TextButton(onPressed: busy ? null : () => action(() async {
          await widget.user.sendEmailVerification();
          if (mounted) setState(() => message = 'Verification email sent.');
        }), child: const Text('Send verification email')),
        TextButton(onPressed: busy ? null : () => action(() => widget.user.reload()), child: const Text('I have verified my email')),
      ],
      const SizedBox(height: 20),
      FirebaseProfileEditor(key:ValueKey(widget.user.uid),api:profileApi,initialName:widget.user.displayName??''),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FirebaseRoomsPage(api:profileApi))),icon:const Icon(Icons.meeting_room),label:const Text('Open rooms')),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FirebaseGreedyWheelPage(api:profileApi))),icon:const Icon(Icons.casino_rounded),label:const Text('Greedy Wheel · Shared server round')),
      const SizedBox(height:10),
      const Text('Uploaded Greedy Wheel can start only after its server and real wallet are verified. No demo coins or fake winners.'),
      if (message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(message!)),
      TextButton(onPressed: busy ? null : () => action(() async {
        await FirebaseAuth.instance.signOut();
        try { await GoogleSignIn.instance.signOut(); } catch (_) { /* Firebase session is already cleared. */ }
      }), child: const Text('Sign out')),
    ]),
  );
}

class _CelebrationSession extends StatefulWidget {
  final User user; final Widget child;
  const _CelebrationSession({super.key,required this.user,required this.child});
  @override State<_CelebrationSession> createState()=>_CelebrationSessionState();
}
class _CelebrationSessionState extends State<_CelebrationSession>{
  final client=http.Client();
  late final api=FirebaseProfileApi(uid:widget.user.uid,client:client,token:()async=>FirebaseAuth.instance.currentUser?.uid==widget.user.uid?widget.user.getIdToken():null);
  @override void dispose(){client.close();super.dispose();}
  @override Widget build(BuildContext context)=>GlobalCelebrationLayer(api:api,child:PersistentRoomLayer(api:api,child:widget.child));
}
