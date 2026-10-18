# Coin sellers and wallet

The app reads an owner-published seller directory and the signed-in user's private wallet. No seeded sellers or balances are shipped. The directory supports name/ID search, country filtering, pagination, seller details and ID copy. Recharge support opens the existing ticket flow.

`WALLET_SCHEMA.sql` is applied to the Sovera Supabase project. `sovera_coin_sellers` contains public, owner-approved listing fields only; clients can read published rows and cannot create/approve/edit listings. Publish a listing only after verifying the seller's actual profile UID and business details. Seller quotas and applications remain private in the existing reseller tables.

`sovera_wallets` provisions an account without fabricating credit. `sovera_wallet_entries` is the authoritative posted ledger; the security-invoker balance view sums signed deltas for the caller's wallet. Only authenticated owners can read their wallet and entries. All client write privileges are revoked. History is paginated in stable descending creation/id order. Coins and Diamonds remain separate integers; balances return as strings to preserve precision.

This release enables reads only. No purchase, recharge transfer, gift settlement or exchange RPC is exposed. A future trusted backend must enforce nonnegative balances under row locking, idempotency, freezes and double-entry transfer invariants in one transaction before enabling those operations. Do not insert production ledger rows manually as a replacement for such settlement logic. The displayed exchange rate is informational.

Google sign-in still requires provider configuration. Guest mode shows no invented wallet. Seller/transaction screenshots in automated tests use explicit fixture data only; they are not production listings.
