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
for permission in ['RECORD_AUDIO','ACCESS_NETWORK_STATE','MODIFY_AUDIO_SETTINGS']:
 name='android.permission.'+permission
 if not any(e.get('{'+NS+'}name')==name for e in root.findall('uses-permission')):
  ET.SubElement(root,'uses-permission',{'{'+NS+'}name':name})
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
data['NSPhotoLibraryUsageDescription']='Choose a profile picture for your Sovera room.'
data['NSMicrophoneUsageDescription']='Speak in a Sovera voice room when you enable your microphone.'
data['FlutterDeepLinkingEnabled']=False
with p.open('wb') as file:plistlib.dump(data,file)


# Enable microphone requests with CocoaPods; no camera or blanket photo access.
p=Path('ios/Podfile')
if p.exists():
 text=p.read_text()
 marker='flutter_additional_ios_build_settings(target)'
 if marker in text and 'PERMISSION_MICROPHONE=1' not in text:
  text=text.replace(marker,marker+"\n    target.build_configurations.each do |config|\n      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_MICROPHONE=1']\n    end")
  p.write_text(text)

# permission_handler_android 13 requires API 37; retain the existing target/min SDK.
p=Path('android/app/build.gradle.kts')
if p.exists():
 text=p.read_text().replace('compileSdk = flutter.compileSdkVersion','compileSdk = 37')
 p.write_text(text)
