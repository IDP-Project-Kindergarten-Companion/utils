# Ensure these match your port-forwarding setup and service prefixes
AUTH_BASE_URL="http://localhost:8081/auth"
DB_INTERACT_BASE_URL="http://localhost:8082"

# Step 1: Register a Parent User
# (Using unique details to avoid conflicts if run multiple times)
PARENT_USERNAME="curl_parent_$(date +%s)"
PARENT_EMAIL="${PARENT_USERNAME}@example.com"
echo "Registering Parent: ${PARENT_USERNAME}"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{
        \"username\": \"${PARENT_USERNAME}\",
        \"password\": \"password123\",
        \"role\": \"parent\",
        \"email\": \"${PARENT_EMAIL}\",
        \"first_name\": \"CURL_Parent\",
        \"last_name\": \"Test\"
      }" \
  ${AUTH_BASE_URL}/register
# Expected: 201 Created, JSON response with "message" and "user_id"

echo -e "\n\n--- Register Teacher ---"

# Step 2: Register a Teacher User
TEACHER_USERNAME="curl_teacher_$(date +%s)"
TEACHER_EMAIL="${TEACHER_USERNAME}@example.com"
echo "Registering Teacher: ${TEACHER_USERNAME}"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{
        \"username\": \"${TEACHER_USERNAME}\",
        \"password\": \"password456\",
        \"role\": \"teacher\",
        \"email\": \"${TEACHER_EMAIL}\",
        \"first_name\": \"CURL_Teacher\",
        \"last_name\": \"Test\"
      }" \
  ${AUTH_BASE_URL}/register
# Expected: 201 Created, JSON response with "message" and "user_id"

echo -e "\n\n--- Login Parent ---"

# Step 3: Login as Parent and Capture Token & User ID
# (If not using jq, manually copy 'access_token' and 'user_id' from the output)
echo "Logging in as Parent: ${PARENT_USERNAME}"
PARENT_LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{
        \"username\": \"${PARENT_USERNAME}\",
        \"password\": \"password123\"
      }" \
  ${AUTH_BASE_URL}/login)

echo "Parent Login Response JSON: ${PARENT_LOGIN_RESPONSE}"
PARENT_TOKEN=$(echo "${PARENT_LOGIN_RESPONSE}" | jq -r .access_token)
PARENT_USER_ID=$(echo "${PARENT_LOGIN_RESPONSE}" | jq -r .user_id)
echo "Parent Access Token: ${PARENT_TOKEN}"
echo "Parent User ID: ${PARENT_USER_ID}"
# Expected: 200 OK, JSON response with "access_token", "refresh_token", "role", "user_id"

echo -e "\n\n--- Login Teacher ---"

# Step 4: Login as Teacher and Capture Token & User ID
echo "Logging in as Teacher: ${TEACHER_USERNAME}"
TEACHER_LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{
        \"username\": \"${TEACHER_USERNAME}\",
        \"password\": \"password456\"
      }" \
  ${AUTH_BASE_URL}/login)

echo "Teacher Login Response JSON: ${TEACHER_LOGIN_RESPONSE}"
TEACHER_TOKEN=$(echo "${TEACHER_LOGIN_RESPONSE}" | jq -r .access_token)
TEACHER_USER_ID=$(echo "${TEACHER_LOGIN_RESPONSE}" | jq -r .user_id)
echo "Teacher Access Token: ${TEACHER_TOKEN}"
echo "Teacher User ID: ${TEACHER_USER_ID}"
# Expected: 200 OK, JSON response with "access_token", "refresh_token", "role", "user_id"

echo -e "\n\n--- Get Current User (Parent) ---"

# Step 5: (Optional) Test /me endpoint for Parent
echo "Testing /auth/me for Parent (User ID: ${PARENT_USER_ID})"
curl -H "Authorization: Bearer ${PARENT_TOKEN}" ${AUTH_BASE_URL}/me
# Expected: 200 OK, JSON response with user details (user_id, username, role, etc.)

echo -e "\n\n"

# Step 6: Create a Child (as Parent)
echo "--- Create Child (as Parent) ---"
echo "Using Parent Token: ${PARENT_TOKEN}"
CHILD_CREATE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  -d '{
        "name": "CURL Child One",
        "birthday": "2023-03-15",
        "group": "Explorers",
        "allergies": ["Dust", "Pollen"],
        "notes": "Loves building blocks via CURL commands"
      }' \
  ${DB_INTERACT_BASE_URL}/internal/children)

echo "Child Create Response JSON: ${CHILD_CREATE_RESPONSE}"
CHILD_ID=$(echo "${CHILD_CREATE_RESPONSE}" | jq -r .child_id)
echo "Created Child ID: ${CHILD_ID}"
# Expected: 201 Created, JSON response with "child_id" and "message"

echo -e "\n\n--- Link Supervisor to Child (as Teacher) ---"

# Step 7: Link Supervisor (Teacher) to Child (as Teacher)
echo "Using Teacher Token: ${TEACHER_TOKEN}"
echo "Linking Teacher (ID: ${TEACHER_USER_ID}) to Child (ID: ${CHILD_ID})"
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"supervisor_id\": \"${TEACHER_USER_ID}\"
      }" \
  ${DB_INTERACT_BASE_URL}/internal/children/${CHILD_ID}/link-supervisor
# Expected: 200 OK, JSON response with "message"

echo -e "\n\n--- Get Child Data (as Parent, after linking) ---"

# Step 8: Get Child Data (as Parent, after linking)
echo "Fetching data for Child ID: ${CHILD_ID} (as Parent)"
curl -H "Authorization: Bearer ${PARENT_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/children/${CHILD_ID}
# Expected: 200 OK, JSON response with child details, including "supervisor_ids" array containing TEACHER_USER_ID

echo -e "\n\n--- Get Child Data (as Teacher, after linking) ---"

# Step 9: Get Child Data (as Teacher, after linking)
echo "Fetching data for Child ID: ${CHILD_ID} (as Teacher)"
curl -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/children/${CHILD_ID}
# Expected: 200 OK, JSON response with child details

echo -e "\n\n--- Get Children List (as Parent) ---"

# Step 10: Get Children List (as Parent)
curl -H "Authorization: Bearer ${PARENT_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/children
# Expected: 200 OK, JSON array of children linked to the parent, should include the child created above

echo -e "\n\n--- Get Children List (as Teacher) ---"

# Step 11: Get Children List (as Teacher)
curl -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/children
# Expected: 200 OK, JSON array of children linked to the teacher, should include the child linked above

echo -e "\n\n--- Create Activity for Child (as Teacher) ---"

# Step 12: Create an Activity for the Child (as Teacher)
echo "Creating Activity for Child ID: ${CHILD_ID} (as Teacher)"
ACTIVITY_CREATE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d "{
        \"child_id\": \"${CHILD_ID}\",
        \"type\": \"nap\",
        \"details\": {
            \"duration_minutes\": 75,
            \"quality\": \"soundly\",
            \"notes\": \"Slept well after extensive CURL testing.\"
        }
      }" \
  ${DB_INTERACT_BASE_URL}/internal/activities)

echo "Activity Create Response JSON: ${ACTIVITY_CREATE_RESPONSE}"
ACTIVITY_ID=$(echo "${ACTIVITY_CREATE_RESPONSE}" | jq -r .activity_id)
echo "Created Activity ID: ${ACTIVITY_ID}"
# Expected: 201 Created, JSON response with "activity_id" and "message"

echo -e "\n\n--- Get Activities for Child (as Teacher) ---"

# Step 13: Get Activities for the Child (as Teacher)
echo "Fetching Activities for Child ID: ${CHILD_ID} (as Teacher)"
curl -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  "${DB_INTERACT_BASE_URL}/data/activities?child_id=${CHILD_ID}"
# Expected: 200 OK, JSON array of activities, should include the one created above

echo -e "\n\n--- Update Child Details (as Teacher) ---"

# Step 14: Update Child Details (as an authorized user, e.g., Teacher)
echo "Updating Child (ID: ${CHILD_ID}) Details (as Teacher)"
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  -d '{
        "group": "Super Testers",
        "notes": "Child is now proficient in CURL scripting."
      }' \
  ${DB_INTERACT_BASE_URL}/internal/children/${CHILD_ID}
# Expected: 200 OK, JSON response with "message": "Child details updated"
# Verify by getting child data again (e.g., Step 8 or 9) to see the changes.

echo -e "\n\n--- Delete Activity (Attempt as Parent - SHOULD FAIL) ---"

# Step 15: Delete Activity (Attempt as Parent - Should Fail)
echo "Attempting to Delete Activity (ID: ${ACTIVITY_ID}) as Parent (SHOULD FAIL)"
curl -X DELETE \
  -H "Authorization: Bearer ${PARENT_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/activities/${ACTIVITY_ID}
# Expected: 403 Forbidden (or similar, based on your db-interact's authorization logic)

echo -e "\n\n--- Delete Activity (as Teacher - SHOULD SUCCEED) ---"

# Step 16: Delete Activity (as Teacher - Should Succeed)
echo "Deleting Activity (ID: ${ACTIVITY_ID}) as Teacher (SHOULD SUCCEED)"
curl -X DELETE \
  -H "Authorization: Bearer ${TEACHER_TOKEN}" \
  ${DB_INTERACT_BASE_URL}/data/activities/${ACTIVITY_ID}
# Expected: 200 OK, JSON response with "message"
# Verify by trying to get activities again (e.g., Step 13) - the deleted activity should be gone.

echo -e "\n\n"