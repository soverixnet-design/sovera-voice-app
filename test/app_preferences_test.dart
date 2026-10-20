import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sovera/app_preferences.dart';

void main(){
  test('low data preference survives reload',()async{
    SharedPreferences.setMockInitialValues({});
    await SoveraPreferences.load();
    expect(SoveraPreferences.lowData.value,false);
    await SoveraPreferences.setLowData(true);
    SoveraPreferences.lowData.value=false;
    await SoveraPreferences.load();
    expect(SoveraPreferences.lowData.value,true);
    await SoveraPreferences.setLowData(false);
  });
  test('cache rejects arbitrary names and private URLs',(){
    expect(CatalogMediaCache.valid('a'*64),true);
    expect(CatalogMediaCache.valid('../wallet'),false);
    expect(CatalogMediaCache.valid('https://example.com'),false);
  });
}
