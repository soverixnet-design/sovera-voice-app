import 'package:flutter/material.dart';

// Pure country-picker UI, completely independent of Firebase/Supabase data.
String countryFlag(dynamic value) {
  final code=(value??'').toString().trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return String.fromCharCodes(code.codeUnits.map((v)=>v+127397));
}
const soveraCountries=<String,String>{
 'BD':'Bangladesh','OM':'Oman','SA':'Saudi Arabia','AE':'United Arab Emirates','QA':'Qatar','KW':'Kuwait','BH':'Bahrain','MY':'Malaysia','IN':'India','PK':'Pakistan','NP':'Nepal','LK':'Sri Lanka','ID':'Indonesia','PH':'Philippines','SG':'Singapore','TH':'Thailand','VN':'Vietnam','MM':'Myanmar','CN':'China','JP':'Japan','KR':'South Korea','AU':'Australia','NZ':'New Zealand','GB':'United Kingdom','US':'United States','CA':'Canada','DE':'Germany','FR':'France','IT':'Italy','ES':'Spain','PT':'Portugal','NL':'Netherlands','SE':'Sweden','NO':'Norway','FI':'Finland','DK':'Denmark','IE':'Ireland','CH':'Switzerland','AT':'Austria','BE':'Belgium','PL':'Poland','GR':'Greece','TR':'Türkiye','RU':'Russia','UA':'Ukraine','EG':'Egypt','MA':'Morocco','DZ':'Algeria','TN':'Tunisia','ZA':'South Africa','NG':'Nigeria','KE':'Kenya','GH':'Ghana','ET':'Ethiopia','AF':'Afghanistan','IR':'Iran','IQ':'Iraq','JO':'Jordan','LB':'Lebanon','YE':'Yemen','SY':'Syria','PS':'Palestine','MV':'Maldives','BN':'Brunei','UZ':'Uzbekistan','KZ':'Kazakhstan','BR':'Brazil','AR':'Argentina','MX':'Mexico','CO':'Colombia','CL':'Chile','PE':'Peru','CU':'Cuba','HK':'Hong Kong','TW':'Taiwan','KH':'Cambodia','LA':'Laos','MN':'Mongolia','BT':'Bhutan','MU':'Mauritius','SC':'Seychelles','SD':'Sudan','SO':'Somalia','LY':'Libya','AL':'Albania','BA':'Bosnia and Herzegovina','RO':'Romania','HU':'Hungary','CZ':'Czechia','SK':'Slovakia','HR':'Croatia','RS':'Serbia','BG':'Bulgaria','IS':'Iceland','LU':'Luxembourg','MT':'Malta','CY':'Cyprus','EE':'Estonia','LV':'Latvia','LT':'Lithuania','GE':'Georgia','AM':'Armenia','AZ':'Azerbaijan','KG':'Kyrgyzstan','TJ':'Tajikistan','TM':'Turkmenistan',
};
class CountryPicker extends StatelessWidget{
 final String value;final ValueChanged<String>? onChanged;
 const CountryPicker({super.key,required this.value,required this.onChanged});
 @override Widget build(BuildContext context)=>ListTile(contentPadding:EdgeInsets.zero,leading:Text(value.isEmpty?'🌍':countryFlag(value),style:const TextStyle(fontSize:28)),title:const Text('Country'),subtitle:Text(soveraCountries[value]??(value.isEmpty?'Choose your country':value)),trailing:const Icon(Icons.expand_more),onTap:onChanged==null?null:()async{final result=await showSearch<String?>(context:context,delegate:_CountrySearch());if(result!=null)onChanged!(result);});
}
class _CountrySearch extends SearchDelegate<String?>{
 @override List<Widget> buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
 @override Widget buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,null),icon:const Icon(Icons.arrow_back));
 @override Widget buildResults(BuildContext context)=>buildSuggestions(context);
 @override Widget buildSuggestions(BuildContext context){final rows=soveraCountries.entries.where((e)=>e.value.toLowerCase().contains(query.toLowerCase())||e.key.toLowerCase()==query.toLowerCase()).toList();return ListView(children:[for(final e in rows)ListTile(leading:Text(countryFlag(e.key),style:const TextStyle(fontSize:28)),title:Text(e.value),onTap:()=>close(context,e.key))]);}
}
class RoomCountryDialog extends StatefulWidget{
 const RoomCountryDialog({super.key});
 @override State<RoomCountryDialog> createState()=>_RoomCountryDialogState();
}
class _RoomCountryDialogState extends State<RoomCountryDialog>{
 String country='';
 @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Room country'),content:CountryPicker(value:country,onChanged:(value)=>setState(()=>country=value)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:country.isEmpty?null:()=>Navigator.pop(context,country),child:const Text('Save'))]);
}
).hasMatch(code))return '';
  return String.fromCharCodes(code.codeUnits.map((v)=>v+127397));
}
const soveraCountries=<String,String>{
 'BD':'Bangladesh','OM':'Oman','SA':'Saudi Arabia','AE':'United Arab Emirates','QA':'Qatar','KW':'Kuwait','BH':'Bahrain','MY':'Malaysia','IN':'India','PK':'Pakistan','NP':'Nepal','LK':'Sri Lanka','ID':'Indonesia','PH':'Philippines','SG':'Singapore','TH':'Thailand','VN':'Vietnam','MM':'Myanmar','CN':'China','JP':'Japan','KR':'South Korea','AU':'Australia','NZ':'New Zealand','GB':'United Kingdom','US':'United States','CA':'Canada','DE':'Germany','FR':'France','IT':'Italy','ES':'Spain','PT':'Portugal','NL':'Netherlands','SE':'Sweden','NO':'Norway','FI':'Finland','DK':'Denmark','IE':'Ireland','CH':'Switzerland','AT':'Austria','BE':'Belgium','PL':'Poland','GR':'Greece','TR':'Türkiye','RU':'Russia','UA':'Ukraine','EG':'Egypt','MA':'Morocco','DZ':'Algeria','TN':'Tunisia','ZA':'South Africa','NG':'Nigeria','KE':'Kenya','GH':'Ghana','ET':'Ethiopia','AF':'Afghanistan','IR':'Iran','IQ':'Iraq','JO':'Jordan','LB':'Lebanon','YE':'Yemen','SY':'Syria','PS':'Palestine','MV':'Maldives','BN':'Brunei','UZ':'Uzbekistan','KZ':'Kazakhstan','BR':'Brazil','AR':'Argentina','MX':'Mexico','CO':'Colombia','CL':'Chile','PE':'Peru','CU':'Cuba','HK':'Hong Kong','TW':'Taiwan','KH':'Cambodia','LA':'Laos','MN':'Mongolia','BT':'Bhutan','MU':'Mauritius','SC':'Seychelles','SD':'Sudan','SO':'Somalia','LY':'Libya','AL':'Albania','BA':'Bosnia and Herzegovina','RO':'Romania','HU':'Hungary','CZ':'Czechia','SK':'Slovakia','HR':'Croatia','RS':'Serbia','BG':'Bulgaria','IS':'Iceland','LU':'Luxembourg','MT':'Malta','CY':'Cyprus','EE':'Estonia','LV':'Latvia','LT':'Lithuania','GE':'Georgia','AM':'Armenia','AZ':'Azerbaijan','KG':'Kyrgyzstan','TJ':'Tajikistan','TM':'Turkmenistan',
};
class CountryPicker extends StatelessWidget{
 final String value;final ValueChanged<String>? onChanged;
 const CountryPicker({super.key,required this.value,required this.onChanged});
 @override Widget build(BuildContext context)=>ListTile(contentPadding:EdgeInsets.zero,leading:Text(value.isEmpty?'🌍':countryFlag(value),style:const TextStyle(fontSize:28)),title:const Text('Country'),subtitle:Text(soveraCountries[value]??(value.isEmpty?'Choose your country':value)),trailing:const Icon(Icons.expand_more),onTap:onChanged==null?null:()async{final result=await showSearch<String?>(context:context,delegate:_CountrySearch());if(result!=null)onChanged!(result);});
}
class _CountrySearch extends SearchDelegate<String?>{
 @override List<Widget> buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
 @override Widget buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,null),icon:const Icon(Icons.arrow_back));
 @override Widget buildResults(BuildContext context)=>buildSuggestions(context);
 @override Widget buildSuggestions(BuildContext context){final rows=soveraCountries.entries.where((e)=>e.value.toLowerCase().contains(query.toLowerCase())||e.key.toLowerCase()==query.toLowerCase()).toList();return ListView(children:[for(final e in rows)ListTile(leading:Text(countryFlag(e.key),style:const TextStyle(fontSize:28)),title:Text(e.value),onTap:()=>close(context,e.key))]);}
}
class RoomCountryDialog extends StatefulWidget{
 const RoomCountryDialog({super.key});
 @override State<RoomCountryDialog> createState()=>_RoomCountryDialogState();
}
class _RoomCountryDialogState extends State<RoomCountryDialog>{
 String country='';
 @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Room country'),content:CountryPicker(value:country,onChanged:(value)=>setState(()=>country=value)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:country.isEmpty?null:()=>Navigator.pop(context,country),child:const Text('Save'))]);
}
