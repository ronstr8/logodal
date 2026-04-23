-- Existing passkeys were stored without real cryptographic verification and are unusable.
-- Change column types to TEXT so we can store base64url strings from the WebAuthn library.
DELETE FROM player_passkeys;
ALTER TABLE player_passkeys
    ALTER COLUMN credential_id TYPE TEXT USING encode(credential_id, 'escape'),
    ALTER COLUMN public_key    TYPE TEXT USING encode(public_key,    'escape');
