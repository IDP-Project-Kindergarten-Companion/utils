#!/bin/bash

# Script to run comprehensive tests for Child Profile Service
# Ensure kubectl port-forward for auth-svc (e.g., 8081:5051)
# and child-profile-svc (e.g., 8083:5002) are running in separate terminals.

# --- Step 1: Define Base URLs ---
AUTH_BASE_URL="http://localhost:8081/auth"
CHILD_PROFILE_BASE_URL="http://localhost:8083/profiles"

echo "--- Comprehensive Test Suite for Child Profile Service ---"
echo "Using AUTH_BASE_URL: ${AUTH_BASE_URL}"
echo "Using CHILD_PROFILE_BASE_URL: ${CHILD_PROFILE_BASE_URL}"

# Function to print a separator
print_separator() {
  echo -e "\n------------------------------------------------------------------------------------\n"
}

# --- Step 2: Register and Login Users ---
echo "--- Setting up Users ---"
PARENT_USERNAME="testparent_$(date +%s)"
PARENT_EMAIL="${PARENT_USERNAME}@example.com"
curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${PARENT_USERNAME}\", \"password\": \"password123\", \"role\": \"parent\", \"email\": \"${PARENT_EMAIL}\", \"first_name\": \"Test\", \"last_name\": \"Parent1\"}" "${AUTH_BASE_URL}/register" > /dev/null
PARENT_LOGIN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${PARENT_USERNAME}\", \"password\": \"password123\"}" "${AUTH_BASE_URL}/login")
PARENT_TOKEN=$(echo "${PARENT_LOGIN_RESPONSE}" | jq -r .access_token)
PARENT_USER_ID=$(echo "${PARENT_LOGIN_RESPONSE}" | jq -r .user_id)
echo "Parent 1 (${PARENT_USERNAME}) Token: ${PARENT_TOKEN}"

SECOND_PARENT_USERNAME="testparent2_$(date +%s)"
SECOND_PARENT_EMAIL="${SECOND_PARENT_USERNAME}@example.com"
curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${SECOND_PARENT_USERNAME}\", \"password\": \"password123\", \"role\": \"parent\", \"email\": \"${SECOND_PARENT_EMAIL}\", \"first_name\": \"Test\", \"last_name\": \"Parent2\"}" "${AUTH_BASE_URL}/register" > /dev/null
SECOND_PARENT_LOGIN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${SECOND_PARENT_USERNAME}\", \"password\": \"password123\"}" "${AUTH_BASE_URL}/login")
SECOND_PARENT_TOKEN=$(echo "${SECOND_PARENT_LOGIN_RESPONSE}" | jq -r .access_token)
echo "Parent 2 (${SECOND_PARENT_USERNAME}) Token: ${SECOND_PARENT_TOKEN}"

TEACHER_USERNAME="testteacher_$(date +%s)"
TEACHER_EMAIL="${TEACHER_USERNAME}@example.com"
curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${TEACHER_USERNAME}\", \"password\": \"teacherpass\", \"role\": \"teacher\", \"email\": \"${TEACHER_EMAIL}\", \"first_name\": \"Test\", \"last_name\": \"Teacher1\"}" "${AUTH_BASE_URL}/register" > /dev/null
TEACHER_LOGIN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${TEACHER_USERNAME}\", \"password\": \"teacherpass\"}" "${AUTH_BASE_URL}/login")
TEACHER_TOKEN=$(echo "${TEACHER_LOGIN_RESPONSE}" | jq -r .access_token)
TEACHER_USER_ID=$(echo "${TEACHER_LOGIN_RESPONSE}" | jq -r .user_id)
echo "Teacher 1 (${TEACHER_USERNAME}) Token: ${TEACHER_TOKEN}"
echo "Teacher 1 User ID: ${TEACHER_USER_ID}"

UNLINKED_TEACHER_USERNAME="testteacher2_$(date +%s)"
UNLINKED_TEACHER_EMAIL="${UNLINKED_TEACHER_USERNAME}@example.com"
curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${UNLINKED_TEACHER_USERNAME}\", \"password\": \"teacherpass\", \"role\": \"teacher\", \"email\": \"${UNLINKED_TEACHER_EMAIL}\", \"first_name\": \"Test\", \"last_name\": \"Teacher2\"}" "${AUTH_BASE_URL}/register" > /dev/null
UNLINKED_TEACHER_LOGIN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"username\": \"${UNLINKED_TEACHER_USERNAME}\", \"password\": \"teacherpass\"}" "${AUTH_BASE_URL}/login")
UNLINKED_TEACHER_TOKEN=$(echo "${UNLINKED_TEACHER_LOGIN_RESPONSE}" | jq -r .access_token)
echo "Teacher 2 (Unlinked) (${UNLINKED_TEACHER_USERNAME}) Token: ${UNLINKED_TEACHER_TOKEN}"

print_separator

# --- Step 3: Child Profile CRUD and Linking ---
echo "--- Testing Child Profile CRUD & Linking ---"
CHILD_NAME_UNIQUE="Kid_$(date +%s%N)"
echo "Parent 1 attempting to add child: ${CHILD_NAME_UNIQUE}"
CHILD_ADD_RESPONSE=$(curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  -d "{
        \"name\": \"${CHILD_NAME_UNIQUE}\",
        \"birthday\": \"2023-08-01\",
        \"group\": \"Star Gazers\",
        \"allergies\": [\"Pollen\"],
        \"notes\": \"Initial child record\"
      }" \
  "${CHILD_PROFILE_BASE_URL}/children")

echo "Child Add Response: ${CHILD_ADD_RESPONSE}"
NEW_CHILD_ID=$(echo "${CHILD_ADD_RESPONSE}" | grep -o '"child_id":"[^"]*' | grep -o '[^"]*$' | tail -n 1)
LINKING_CODE=$(echo "${CHILD_ADD_RESPONSE}" | grep -o '"linking_code":"[^"]*' | grep -o '[^"]*$' | tail -n 1)

if [ -z "${NEW_CHILD_ID}" ]; then echo "ERROR: Child creation failed to return child_id."; exit 1; fi
if [ -z "${LINKING_CODE}" ]; then echo "ERROR: Child creation failed to return linking_code."; exit 1; fi
echo "Created Child ID: ${NEW_CHILD_ID}"
echo "Linking Code: ${LINKING_CODE}"
print_separator

echo "Teacher 1 (ID: ${TEACHER_USER_ID}) linking to Child (ID: ${NEW_CHILD_ID})"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{\"linking_code\": \"${LINKING_CODE}\"}" \
  "${CHILD_PROFILE_BASE_URL}/children/link-supervisor"
print_separator

echo "Parent 1 verifying supervisor link for child ID: ${NEW_CHILD_ID}"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

echo "Teacher 1 verifying access to child ID: ${NEW_CHILD_ID} after linking"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

# --- Step 4: Error Cases for Add Child ---
echo "--- Testing Add Child Error Cases ---"
echo "Attempting to add child with missing 'name' (as Parent 1)"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  -d "{
        \"birthday\": \"2023-08-02\",
        \"group\": \"Moon Walkers\"
      }" \
  "${CHILD_PROFILE_BASE_URL}/children"
print_separator

echo "Attempting to add child as Teacher 1 (should be forbidden)"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"name\": \"TeacherAddedChild\",
        \"birthday\": \"2023-08-03\",
        \"group\": \"Sun Watchers\"
      }" \
  "${CHILD_PROFILE_BASE_URL}/children"
print_separator

# --- Step 5: Error Cases for Link Supervisor ---
echo "--- Testing Link Supervisor Error Cases ---"
echo "Teacher 1 attempting to link with an INVALID linking code"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{\"linking_code\": \"INVALID_FAKE_CODE_123\"}" \
  "${CHILD_PROFILE_BASE_URL}/children/link-supervisor"
print_separator

echo "Parent 1 attempting to use link-supervisor endpoint (should be forbidden)"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  -d "{\"linking_code\": \"${LINKING_CODE}\"}" \
  "${CHILD_PROFILE_BASE_URL}/children/link-supervisor" 
print_separator

# --- Step 6: Authorization Tests for Get/Update Specific Child ---
echo "--- Testing Get/Update Authorization ---"
echo "Parent 2 (unlinked) attempting to GET child ID: ${NEW_CHILD_ID}"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
  -H "Authorization: Bearer ${SECOND_PARENT_TOKEN}" \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

echo "Teacher 2 (unlinked) attempting to GET child ID: ${NEW_CHILD_ID}"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
  -H "Authorization: Bearer ${UNLINKED_TEACHER_TOKEN}" \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

echo "Parent 2 (unlinked) attempting to UPDATE child ID: ${NEW_CHILD_ID}"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X PUT \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SECOND_PARENT_TOKEN}" \
  -d '{"notes": "Attempted update by Parent 2"}' \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

# --- Step 7: Update by Linked Teacher (Should be allowed if your service logic permits) ---
# Note: Your current child-profile-service PUT endpoint only checks if the requester is the original parent.
# If teachers are allowed to update via this endpoint (after linking), this test would verify that.
# If not, it should return 403 Forbidden.
echo "Teacher 1 (linked) attempting to UPDATE child ID: ${NEW_CHILD_ID} with new allergies"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X PUT \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d '{
        "allergies": ["Dairy", "Gluten"]
      }' \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator

echo "Parent 1 verifying Teacher's update for child ID: ${NEW_CHILD_ID}"
curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
print_separator


# --- Step 8: (Optional) Test Deleting a Child ---
# This depends on whether you have implemented DELETE /profiles/children/{child_id}
# and what the permissions are (e.g., only original parent can delete).

# echo "--- Testing Delete Child (if implemented) ---"
# echo "Parent 2 (unlinked) attempting to DELETE child ID: ${NEW_CHILD_ID} (should fail)"
# curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X DELETE \
#   -H "Authorization: Bearer ${SECOND_PARENT_TOKEN}" \
#   "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
# print_separator

# echo "Teacher 1 (linked) attempting to DELETE child ID: ${NEW_CHILD_ID} (should likely fail)"
# curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X DELETE \
#   -H "Authorization: Bearer ${TEACHER_TOKEN}" \
#   "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
# print_separator

# echo "Parent 1 (owner) attempting to DELETE child ID: ${NEW_CHILD_ID} (should succeed if implemented)"
# curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X DELETE \
#   -H "Authorization: Bearer ${PARENT_TOKEN}" \
#   "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
# print_separator

# echo "Parent 1 verifying child deletion by trying to GET child ID: ${NEW_CHILD_ID} (should be 404 or 403)"
# curl -s -w "\nHTTP_STATUS_CODE:%{http_code}\n" -X GET \
#   -H "Authorization: Bearer ${PARENT_TOKEN}" \
#   "${CHILD_PROFILE_BASE_URL}/children/${NEW_CHILD_ID}"
# print_separator


echo "--- Comprehensive Test Suite Complete ---"

