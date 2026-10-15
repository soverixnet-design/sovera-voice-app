"""Apply auth callback configuration after flutter create (no secrets)."""
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

NS='http://schemas.android.com/apk/res/android'
ET.register_namespace('android',NS)
p=Path('android/app/src/main/AndroidManifest.xml')
tree=ET.parse(p);root=tree.getroot()
if not any(e.get('{'+NS+'}name')=='android.permission.INTERNET' for e in root.findall('uses-permission')):
 ET.SubElement(root,'uses-permission',{'{'+NS+'}name':'android.permission.INTERNET'})
activity=root.find('application/activity')
assert activity is not None
# Supabase's app_links plugin owns this callback, not Flutter's Router.
ET.SubElement(activity,'meta-data',{'{'+NS+'}name':'flutter_deeplinking_enabled','{'+NS+'}value':'false'})
f=ET.SubElement(activity,'intent-filter')
ET.SubElement(f,'action',{'{'+NS+'}name':'android.intent.action.VIEW'})
for category in ['DEFAULT','BROWSABLE']:
 ET.SubElement(f,'category',{'{'+NS+'}name':'android.intent.category.'+category})
ET.SubElement(f,'data',{'{'+NS+'}scheme':'com.sovera.voice','{'+NS+'}host':'login-callback'})
tree.write(p,encoding='utf-8',xml_declaration=True)
p=Path('ios/Runner/Info.plist')
with p.open('rb') as file:data=plistlib.load(file)
data['CFBundleURLTypes']=[{'CFBundleTypeRole':'Editor','CFBundleURLSchemes':['com.sovera.voice']}]
data['FlutterDeepLinkingEnabled']=False
with p.open('wb') as file:plistlib.dump(data,file)
