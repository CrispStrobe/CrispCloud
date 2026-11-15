// Disposable Developer ID signing acceptance: touches only its UUID-named test item.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
int main(void) { @autoreleasepool {
 NSString *service=[@"com.crispcloud.signing-probe." stringByAppendingString:[NSUUID UUID].UUIDString];
 NSDictionary *base=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
  (__bridge id)kSecAttrService:service,(__bridge id)kSecAttrAccount:@"temporary-probe",
  (__bridge id)kSecUseDataProtectionKeychain:@YES};
 NSMutableDictionary *add=[base mutableCopy];
 NSData *expected=[@"temporary signing probe" dataUsingEncoding:NSUTF8StringEncoding];
 add[(__bridge id)kSecValueData]=expected;
 OSStatus added=SecItemAdd((__bridge CFDictionaryRef)add,NULL);
 if(added!=errSecSuccess){fprintf(stderr,"Data Protection Keychain add failed: %d\n",(int)added);return 1;}
 NSMutableDictionary *read=[base mutableCopy];read[(__bridge id)kSecReturnData]=@YES;
 CFTypeRef result=NULL;OSStatus copied=SecItemCopyMatching((__bridge CFDictionaryRef)read,&result);
 OSStatus removed=SecItemDelete((__bridge CFDictionaryRef)base);
 BOOL same=copied==errSecSuccess && [(__bridge NSData*)result isEqualToData:expected];
 if(result)CFRelease(result);
 if(!same||removed!=errSecSuccess){fprintf(stderr,"Keychain read/delete failed: %d/%d\n",(int)copied,(int)removed);return 1;}
 puts("Live Developer ID Data Protection Keychain create/read/delete passed");return 0;
 }}
