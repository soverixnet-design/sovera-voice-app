# Frame and entry integration

This update adds five animated avatar frames (Crown Violet, Royal Horses, Solar Crown, Sunrise Crown, Rose Crown) and two animated nameplates from the previously supplied dynamic-name pack. The catalogue contains 19 themes. The composite reference is split into independent assets, with transparent video backgrounds and still fallbacks for reduced motion.

Names render as Flutter text layers using the current profile name. The frame artwork is unchanged when a name changes. Arrival cards show the user's name alongside the design name; the Ice Dragon arrival keeps its complete 4.5-second clip. Dedicated arrivals can be browsed separately. Sound is scoped to the arrival and stops on close/background.

The app remains compatible with the already-active base schema. Additional community onboarding/reward/exchange/connection screens are gated by the presence of the corresponding schema fields. Missing optional presence APIs show an unknown attendance count. Existing signed-in accounts can see explicitly labelled local frame previews.

Bundled preview selection is local to the current session. It is not proof of paid ownership or a server inventory grant, and room arrivals are not yet broadcast to other connected users. The previously prepared inventory/community production migration remains blocked pending its specific authorization; this update does not apply it or bypass the rejected migration.

Asset source: user-supplied sovera-dynamic-name.zip, three original MP4 references. Mobile derivatives are animated WebP with alpha, plus still WebP fallbacks. Original imports remain unchanged.
