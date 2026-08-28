#!/bin/bash
set -e

echo "🚀 Starting filler script at $(date)..."

# ============================================================
# CONFIGURATION
# ============================================================
#KEY_ID="YOUR_KEY_ID"
#ISSUER_ID="YOUR_ISSUER_ID"
#P8_FILE="path/to/AuthKey_XXXXXXXXXX.p8"
#APP_BUNDLE_ID="com.yourcompany.yourapp"
#BUILD_VERSION="1.0.0"    # CFBundleShortVersionString
#BUILD_NUMBER="42"         # CFBundleVersion
#LOCALE="en-US"
#WHAT_TO_TEST="Your What to Test notes here"

KEY_ID="$1"
ISSUER_ID="$2"
P8_FILE="$3"
APP_BUNDLE_ID="$4"
BUILD_VERSION="$5"
BUILD_NUMBER="$6"
WHAT_TO_TEST="$7"

#echo "KEY_ID='$KEY_ID'"
#echo "ISSUER_ID='$ISSUER_ID"
#echo "P8_FILE='$P8_FILE'"
#echo "APP_BUNDLE_ID='$APP_BUNDLE_ID'"
#echo "BUILD_VERSION='$BUILD_VERSION'"
#echo "BUILD_NUMBER='$BUILD_NUMBER'"
#echo "WHAT_TO_TEST='$WHAT_TO_TEST'"

MAX_ATTEMPTS=5      # try up to n times
RETRY_INTERVAL=60    # wait x seconds between attempts


FIRST_DELAY=180
MAX_ATTEMPTS=5      # try up to n times
RETRY_INTERVAL=30    # wait x seconds between attempts


echo "⏳ Waiting $FIRST_DELAY seconds for build to appear in App Store Connect..."
sleep "$FIRST_DELAY"



#exit 0
# ============================================================
#echo STEP 1: Generate JWT
# ============================================================
#HEADER=$(echo -n '{"alg":"ES256","kid":"'"$KEY_ID"'","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
#NOW=$(date +%s)
#EXP=$((NOW + 1200))
#PAYLOAD=$(echo -n '{"iss":"'"$ISSUER_ID"'","iat":'"$NOW"',"exp":'"$EXP"',"aud":"appstoreconnect-v1"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
#SIGNATURE=$(echo -n "$HEADER.$PAYLOAD" | openssl dgst -sha256 -sign "$P8_FILE" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
#JWT="$HEADER.$PAYLOAD.$SIGNATURE"
#echo "✅ JWT generated"


# ============================================================
echo "STEP 1: Generate JWT"
# ============================================================
JWT=$(python3 - <<EOF
import base64, json, time, hashlib, hmac, subprocess

key_id = "$KEY_ID"
issuer_id = "$ISSUER_ID"
p8_file = "$P8_FILE"

# Header and Payload
header = base64.urlsafe_b64encode(
    json.dumps({"alg":"ES256","kid":key_id,"typ":"JWT"}, separators=(',', ':')).encode()
).rstrip(b'=').decode()

now = int(time.time())
payload = base64.urlsafe_b64encode(
    json.dumps({"iss":issuer_id,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}, separators=(',', ':')).encode()
).rstrip(b'=').decode()

# Sign with openssl — output raw binary, convert DER to raw R||S
message = f"{header}.{payload}"
result = subprocess.run(
    ["openssl", "dgst", "-sha256", "-sign", p8_file],
    input=message.encode(),
    capture_output=True
)
der_sig = result.stdout

# Parse DER to extract raw R and S integers (each 32 bytes for P-256)
import struct
assert der_sig[0] == 0x30  # SEQUENCE
seq_len = der_sig[1]
idx = 2
parts = []
for _ in range(2):
    assert der_sig[idx] == 0x02  # INTEGER
    idx += 1
    int_len = der_sig[idx]
    idx += 1
    integer = der_sig[idx:idx+int_len]
    idx += int_len
    # Strip leading zero byte if present (sign byte)
    if integer[0] == 0:
        integer = integer[1:]
    # Pad to 32 bytes
    parts.append(integer.rjust(32, b'\x00'))

raw_sig = parts[0] + parts[1]
signature = base64.urlsafe_b64encode(raw_sig).rstrip(b'=').decode()

print(f"{header}.{payload}.{signature}")
EOF
)
echo "✅ JWT generated"

#echo "JWT: $JWT"

# ============================================================
echo STEP 2: Get App ID
# ============================================================

#RAW_RESPONSE=$(curl -s -g \
#  -H "Authorization: Bearer $JWT" \
#  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=$APP_BUNDLE_ID" 2>&1)

#echo "RAW RESPONSE: $RAW_RESPONSE"


#APP_ID=$(curl -g -s \
#  -H "Authorization: Bearer $JWT" \
#  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=$APP_BUNDLE_ID" \
#  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")


APP_ID=""
for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  echo "🔄 Attempt $i/$MAX_ATTEMPTS: Looking for app..."
  RAW=$(curl -g -s \
    -H "Authorization: Bearer $JWT" \
    "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=$APP_BUNDLE_ID")
  APP_ID=$(echo "$RAW" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(d[0]['id']) if d else print('')" 2>/dev/null)
  if [ -n "$APP_ID" ]; then
    echo "✅ App ID: $APP_ID"
    break
  fi
  echo "⏳ Not found yet, retrying in ${RETRY_INTERVAL}s..."
  sleep $RETRY_INTERVAL
done

if [ -z "$APP_ID" ]; then
  echo "❌ App not found after $((MAX_ATTEMPTS * RETRY_INTERVAL)) seconds. Exiting."
  exit 1
fi

echo "✅ App ID: $APP_ID"

# ============================================================
echo STEP 3: Get Build ID
# ============================================================
BUILD_ID=$(curl -g -s \
  -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=$APP_ID&filter[version]=$BUILD_NUMBER&filter[preReleaseVersion.version]=$BUILD_VERSION&sort=-uploadedDate&limit=1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")
echo "✅ Build ID: $BUILD_ID"

# ============================================================
echo STEP 4: Get or Create betaBuildLocalization
# ============================================================
LOCALIZATION_ID=$(curl -g -s \
  -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/betaBuildLocalizations" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(d[0]['id']) if d else print('')")

if [ -z "$LOCALIZATION_ID" ]; then
  echo "ℹ️  No localization found, creating one..."
  LOCALIZATION_ID=$(curl -g -s -X POST \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations" \
    -d '{
      "data": {
        "type": "betaBuildLocalizations",
        "attributes": {
          "whatsNew": "'"$WHAT_TO_TEST"'"
        },
        "relationships": {
          "build": {
            "data": { "type": "builds", "id": "'"$BUILD_ID"'" }
          }
        }
      }
    }' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
  echo "✅ Localization created: $LOCALIZATION_ID"
else
  # ============================================================
  echo STEP 5: Update "What to test"
  # ============================================================
  echo "ℹ️  Existing localization found: $LOCALIZATION_ID, updating..."
  curl -s -X PATCH \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/$LOCALIZATION_ID" \
    -d '{
      "data": {
        "type": "betaBuildLocalizations",
        "id": "'"$LOCALIZATION_ID"'",
        "attributes": {
          "whatsNew": "'"$WHAT_TO_TEST"'"
        }
      }
    }' \
    | python3 -m json.tool
  echo "✅ What to test updated!"
fi
