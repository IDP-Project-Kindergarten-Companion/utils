#!/bin/bash

# Script to test the activity-log-service locally.
# Assumes auth-service is on localhost:8081, child-profile-service on localhost:8083,
# and activity-log-service on localhost:8084 (via kubectl port-forward).

# --- Configuration ---
AUTH_BASE_URL="http://localhost:8081/auth"
CHILD_PROFILE_BASE_URL="http://localhost:8083/profiles"
ACTIVITY_LOG_BASE_URL="http://localhost:8084/log"

# Function to print a separator
print_separator() {
  echo -e "\n------------------------------------------------------------------------------------\n"
}

# OS detection for date command compatibility
OS_TYPE=$(uname)

get_past_time_iso() {
    local duration_string="$1" # e.g., "-2H", "-1M" for macOS; "-2 hours", "-1 minute" for Linux
    local gnu_duration_string="$2" # e.g., "-2 hours"
    
    if [ "$OS_TYPE" = "Darwin" ]; then # macOS
        date -u -v"${duration_string}" +"%Y-%m-%dT%H:%M:%SZ"
    else # Linux (GNU date)
        date -u -d "${gnu_duration_string}" +"%Y-%m-%dT%H:%M:%SZ"
    fi
}


echo "--- Activity Log Service Test Script ---"
print_separator

# --- Step 1: Register and Login Users (Parent and Teacher) ---
echo "--- Setting up Parent User ---"
PARENT_USERNAME="act_parent_$(date +%s)"
PARENT_EMAIL="${PARENT_USERNAME}@example.com"
REG_PARENT_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${PARENT_USERNAME}\", \"password\": \"password123\", \"role\": \"parent\", \"email\": \"${PARENT_EMAIL}\", \"first_name\": \"ActivityParent\", \"last_name\": \"Test\"}" \
  "${AUTH_BASE_URL}/register" -o /dev/null)
if [ "$REG_PARENT_RESPONSE" -ne 201 ]; then echo "ERROR: Parent registration failed. Status: $REG_PARENT_RESPONSE"; exit 1; fi
echo "Parent (${PARENT_USERNAME}) registered."

PARENT_LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${PARENT_USERNAME}\", \"password\": \"password123\"}" \
  "${AUTH_BASE_URL}/login")
PARENT_TOKEN=$(echo "${PARENT_LOGIN_RESPONSE}" | jq -r .access_token)
if [ "${PARENT_TOKEN}" = "null" ] || [ -z "${PARENT_TOKEN}" ]; then echo "ERROR: Failed to get PARENT token. Login response: ${PARENT_LOGIN_RESPONSE}"; exit 1; fi
echo "Parent (${PARENT_USERNAME}) logged in. Token obtained."
print_separator

echo "--- Setting up Teacher User ---"
TEACHER_USERNAME="act_teacher_$(date +%s)"
TEACHER_EMAIL="${TEACHER_USERNAME}@example.com"
REG_TEACHER_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${TEACHER_USERNAME}\", \"password\": \"teacherpass\", \"role\": \"teacher\", \"email\": \"${TEACHER_EMAIL}\", \"first_name\": \"ActivityTeacher\", \"last_name\": \"Test\"}" \
  "${AUTH_BASE_URL}/register" -o /dev/null)
if [ "$REG_TEACHER_RESPONSE" -ne 201 ]; then echo "ERROR: Teacher registration failed. Status: $REG_TEACHER_RESPONSE"; exit 1; fi
echo "Teacher (${TEACHER_USERNAME}) registered."

TEACHER_LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${TEACHER_USERNAME}\", \"password\": \"teacherpass\"}" \
  "${AUTH_BASE_URL}/login")
TEACHER_TOKEN=$(echo "${TEACHER_LOGIN_RESPONSE}" | jq -r .access_token)
if [ "${TEACHER_TOKEN}" = "null" ] || [ -z "${TEACHER_TOKEN}" ]; then echo "ERROR: Failed to get TEACHER token. Login response: ${TEACHER_LOGIN_RESPONSE}"; exit 1; fi
echo "Teacher (${TEACHER_USERNAME}) logged in. Token obtained."
print_separator

# --- Step 2: Parent Adds a Child (via child-profile-service) ---
CHILD_NAME_FOR_ACTIVITIES="ActKid_$(date +%s%N)"
echo "Parent (${PARENT_USERNAME}) adding child: ${CHILD_NAME_FOR_ACTIVITIES} via child-profile-service..."

echo "Executing verbose curl command for child creation:"
CHILD_ADD_RAW_RESPONSE=$(curl -v -w "\nHTTP_STATUS_CHILD_ADD:%{http_code}\nEND_OF_RESPONSE\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  -d "{
        \"name\": \"${CHILD_NAME_FOR_ACTIVITIES}\",
        \"birthday\": \"2024-01-15\",
        \"group\": \"Busy Bees\",
        \"allergies\": [],
        \"notes\": \"Child for activity logging tests\"
      }" \
  "${CHILD_PROFILE_BASE_URL}/children")

echo "--- RAW CHILD_ADD_RESPONSE START ---"
echo "${CHILD_ADD_RAW_RESPONSE}"
echo "--- RAW CHILD_ADD_RESPONSE END ---"

CHILD_ADD_JSON_RESPONSE=$(echo "${CHILD_ADD_RAW_RESPONSE}" | sed -n '/HTTP_STATUS_CHILD_ADD/q;p')
HTTP_STATUS_CODE_CHILD_ADD=$(echo "${CHILD_ADD_RAW_RESPONSE}" | grep "HTTP_STATUS_CHILD_ADD:" | cut -d':' -f2 | tr -d '[:space:]')

echo "Extracted JSON Response for Child Add: ${CHILD_ADD_JSON_RESPONSE}"
echo "Extracted HTTP Status Code for Child Add: '${HTTP_STATUS_CODE_CHILD_ADD}'"

TARGET_CHILD_ID=$(echo "${CHILD_ADD_JSON_RESPONSE}" | jq -r .child_id)
LINKING_CODE=$(echo "${CHILD_ADD_JSON_RESPONSE}" | jq -r .linking_code)

if [ "${HTTP_STATUS_CODE_CHILD_ADD}" != "201" ] || [ "${TARGET_CHILD_ID}" = "null" ] || [ -z "${TARGET_CHILD_ID}" ]; then
  echo "ERROR: Child creation failed."
  echo "Status Code: ${HTTP_STATUS_CODE_CHILD_ADD}"
  echo "Response Body: ${CHILD_ADD_JSON_RESPONSE}"
  echo "Please check the logs for 'child-profile-service' and 'db-interact-service' in Kubernetes."
  exit 1
fi
if [ "${LINKING_CODE}" = "null" ] || [ -z "${LINKING_CODE}" ]; then
  echo "ERROR: Child creation did not return a linking_code."
  exit 1
fi
echo "Child created by parent. ID: ${TARGET_CHILD_ID}"
echo "Linking code: ${LINKING_CODE}"
print_separator

# --- Step 3: Teacher Links to Child (via child-profile-service) ---
echo "Teacher (${TEACHER_USERNAME}) linking to child ID: ${TARGET_CHILD_ID} via child-profile-service..."
LINK_RESPONSE=$(curl -s -w "\nHTTP_STATUS_LINK_SUPERVISOR:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{\"linking_code\": \"${LINKING_CODE}\"}" \
  "${CHILD_PROFILE_BASE_URL}/children/link-supervisor")
echo "${LINK_RESPONSE}"
HTTP_STATUS_CODE_LINK=$(echo "${LINK_RESPONSE}" | grep "HTTP_STATUS_LINK_SUPERVISOR:" | cut -d':' -f2 | tr -d '[:space:]')
if [ "${HTTP_STATUS_CODE_LINK}" != "200" ]; then echo "ERROR: Supervisor linking failed. Status: ${HTTP_STATUS_CODE_LINK}"; exit 1; fi
echo "Supervisor linked successfully."
print_separator


# --- Step 4: Log Activities (as Teacher) ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ") 

echo "--- Testing /log/meal (as Teacher) ---"
curl -s -w "\nHTTP_STATUS_LOG_MEAL:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"timestamp\": \"${TIMESTAMP}\",
        \"notes\": \"Teacher logged: Enjoyed all the fruit salad.\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/meal"
print_separator

echo "--- Testing /log/nap (as Teacher) ---"
START_TIME=$(get_past_time_iso "-2H" "-2 hours") 
END_TIME=$(get_past_time_iso "-1H" "-1 hour")   
curl -s -w "\nHTTP_STATUS_LOG_NAP:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"startTime\": \"${START_TIME}\",
        \"endTime\": \"${END_TIME}\",
        \"wokeUpDuring\": false,
        \"notes\": \"Teacher logged: Slept soundly for one hour.\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/nap"
print_separator

echo "--- Testing /log/drawing (as Teacher) ---"
DRAWING_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
curl -s -w "\nHTTP_STATUS_LOG_DRAWING:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"timestamp\": \"${DRAWING_TIMESTAMP}\",
        \"photoUrl\": \"http://example.com/drawing123.jpg\",
        \"title\": \"My Awesome Robot\",
        \"description\": \"Teacher logged: A very creative drawing of a robot.\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/drawing"
print_separator

echo "--- Testing /log/behavior (as Teacher) ---"
BEHAVIOR_DATE=$(date -u +"%Y-%m-%d")
curl -s -w "\nHTTP_STATUS_LOG_BEHAVIOR:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"date\": \"${BEHAVIOR_DATE}\",
        \"activities\": [\"Circle Time\", \"Outdoor Play\", \"Story Time\"],
        \"grade\": \"Excellent\",
        \"notes\": \"Teacher logged: Had a wonderful day, very participative!\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/behavior"
print_separator

# --- Step 5: Test Error Cases for Activity Logging ---
echo "--- Testing Activity Logging Error Cases (as Teacher) ---"

echo "Attempting to log meal with MISSING childId:"
curl -s -w "\nHTTP_STATUS_MEAL_NO_CHILDID:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"timestamp\": \"${TIMESTAMP}\",
        \"notes\": \"Meal with no child ID.\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/meal"
print_separator

echo "Attempting to log nap with INVALID timestamp format:"
curl -s -w "\nHTTP_STATUS_NAP_BAD_TS:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"startTime\": \"not-a-date\",
        \"endTime\": \"${END_TIME}\",
        \"wokeUpDuring\": false
      }" \
  "${ACTIVITY_LOG_BASE_URL}/nap"
print_separator

echo "Attempting to log drawing with NO TOKEN:"
curl -s -w "\nHTTP_STATUS_DRAWING_NO_TOKEN:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -d "{
        \"childId\": \"${TARGET_CHILD_ID}\",
        \"timestamp\": \"${DRAWING_TIMESTAMP}\",
        \"photoUrl\": \"http://example.com/drawing_no_token.jpg\"
      }" \
  "${ACTIVITY_LOG_BASE_URL}/drawing"
print_separator

# --- Step 6: (Optional) Verify Activities in DB ---
echo "--- Verification Step (Manual or via db-interact GET endpoint) ---"
echo "To verify, use the following to get activities for child ${TARGET_CHILD_ID} (ensure db-interact is port-forwarded to localhost:8082):"
echo "curl -H \"Authorization: Bearer ${TEACHER_TOKEN}\" \"http://localhost:8082/data/activities?child_id=${TARGET_CHILD_ID}\""
print_separator

echo "--- Activity Log Service Test Script Complete ---"

