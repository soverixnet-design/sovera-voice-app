import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'supabase_config.dart';

typedef EmailSignInAction = Future<String?> Function(String email,String password,bool createAccount);
Future<String?> submitEmailSignIn(String email,String password,bool createAccount)async{
 if(createAccount){
  final result=await soveraClient.auth.signUp(email:email,password:password,emailRedirectTo:soveraRedirectUri);
  return result.session==null?'Check your email to confirm your account, then return to sign in.':null;
 }
 await soveraClient.auth.signInWithPassword(email:email,password:password);
 return null;
}
class EmailSignInPage extends StatefulWidget{
 final EmailSignInAction? onSubmit;
 const EmailSignInPage({super.key,this.onSubmit});
 @override State<EmailSignInPage> createState()=>_EmailSignInPageState();
}
class _EmailSignInPageState extends State<EmailSignInPage>{
 final email=TextEditingController(),password=TextEditingController();
 bool create=false,busy=false,showPassword=false;String? error,message;
 @override void dispose(){email.dispose();password.dispose();super.dispose();}
 bool validEmail()=>RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim());
 Future<void> submit()async{
  if(busy)return;
  if(!validEmail()){setState(()=>error='Enter a valid email address.');return;}
  if(password.text.isEmpty||(create&&password.text.length<8)){setState(()=>error=create?'Use a password with at least 8 characters.':'Enter your password.');return;}
  setState((){busy=true;error=null;message=null;});
  try{final result=await (widget.onSubmit??submitEmailSignIn)(email.text.trim(),password.text,create);if(mounted)setState(()=>message=result);}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not connect. Please retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> reset()async{
  if(busy)return;
  if(!validEmail()){setState(()=>error='Enter your email address first.');return;}
  setState((){busy=true;error=null;message=null;});
  try{await soveraClient.auth.resetPasswordForEmail(email.text.trim(),redirectTo:soveraRedirectUri);if(mounted)setState(()=>message='If this address has an account, a password reset link will arrive by email.');}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not send the reset email. Please retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(create?'Create email account':'Sign in with email')),body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:AutofillGroup(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[TextField(controller:email,enabled:!busy,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],autocorrect:false,textCapitalization:TextCapitalization.none,decoration:const InputDecoration(labelText:'Email address')),const SizedBox(height:16),TextField(controller:password,enabled:!busy,obscureText:!showPassword,autocorrect:false,enableSuggestions:false,autofillHints:[create?AutofillHints.newPassword:AutofillHints.password],onSubmitted:(_)=>submit(),decoration:InputDecoration(labelText:'Password',suffixIcon:IconButton(tooltip:showPassword?'Hide password':'Show password',onPressed:()=>setState(()=>showPassword=!showPassword),icon:Icon(showPassword?Icons.visibility_off:Icons.visibility)))),const SizedBox(height:20),if(error!=null)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(error!,style:const TextStyle(color:Colors.redAccent))),if(message!=null)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(message!)),FilledButton(onPressed:busy?null:submit,child:Text(busy?'Please wait…':create?'Create account':'Sign in')),if(!create)TextButton(onPressed:busy?null:reset,child:const Text('Forgot password?')),TextButton(onPressed:busy?null:(){password.clear();setState((){create=!create;error=null;message=null;});},child:Text(create?'Already have an account? Sign in':'New here? Create an email account')),const Text('Confirm the email sent to you when creating an account. Never share your password or email verification link.',style:TextStyle(fontSize:12,color:Colors.white60))])))));
}
class PasswordRecoveryPage extends StatefulWidget{
 final VoidCallback onSaved;const PasswordRecoveryPage({super.key,required this.onSaved});
 @override State<PasswordRecoveryPage> createState()=>_PasswordRecoveryPageState();
}
class _PasswordRecoveryPageState extends State<PasswordRecoveryPage>{
 final password=TextEditingController(),confirm=TextEditingController();bool busy=false;String? error;
 @override void dispose(){password.dispose();confirm.dispose();super.dispose();}
 Future<void> save()async{
  if(busy)return;
  if(password.text.length<8||password.text!=confirm.text){setState(()=>error='Use at least 8 characters and enter the same password twice.');return;}
  setState((){busy=true;error=null;});
  try{await soveraClient.auth.updateUser(UserAttributes(password:password.text));if(mounted)widget.onSaved();}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not update password. Please retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Set a new password')),body:ListView(padding:const EdgeInsets.all(24),children:[TextField(controller:password,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'New password')),TextField(controller:confirm,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'Confirm new password')),if(error!=null)Text(error!),FilledButton(onPressed:busy?null:save,child:Text(busy?'Saving…':'Save password'))]));
}
