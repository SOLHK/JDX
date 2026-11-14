#import <Foundation/Foundation.h>

#ifndef JDX_CONFIG_H
#define JDX_CONFIG_H

#ifndef JDX_BUILD_VERSION
#define JDX_BUILD_VERSION "0.2.1"
#endif

typedef NS_ENUM(NSUInteger, JDXRule) {
    JDXRuleSplash,
    JDXRuleHomeCeiling,
    JDXRuleHomeFloat,
    JDXRuleHomeFloat916,
    JDXRuleHomeTwoScreen,
    JDXRuleHomeBottomAdvertisement,
    JDXRuleHomeBottomAll,
    JDXRuleHomeRecommendations,
    JDXRuleSearchProducts,
    JDXRuleSearchTopShop,
    JDXRuleSearchBeltShop,
    JDXRuleSearchRecommendations,
    JDXRuleMyRecommendations,
    JDXRuleDetailRecommendations,
    JDXRuleCount
};

typedef struct {
    const char *identifier;
    const char *title;
    const char *detail;
    NSUInteger group;
    BOOL recommended;
} JDXRuleDefinition;

typedef NS_ENUM(NSUInteger, JDXProfile) {
    JDXProfileRecommended,
    JDXProfileBlockAll,
    JDXProfileKeepAll
};

extern const JDXRuleDefinition JDXRules[JDXRuleCount];
extern NSString *const JDXConfigurationDidChangeNotification;

void JDXConfigurationStart(BOOL compatible);
BOOL JDXConfigurationCompatible(void);
BOOL JDXMasterEnabled(void);
BOOL JDXRuleEnabled(JDXRule rule);
BOOL JDXShouldBlock(JDXRule rule);
void JDXSetMasterEnabled(BOOL enabled);
void JDXSetRuleEnabled(JDXRule rule, BOOL enabled);
void JDXSetEnhancedEnabled(BOOL enabled);
void JDXApplyProfile(JDXProfile profile);
NSString *JDXRuleIdentifier(JDXRule rule);
NSDictionary *JDXConfigurationSnapshot(void);

#endif
