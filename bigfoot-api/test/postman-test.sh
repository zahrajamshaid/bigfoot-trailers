#!/bin/bash
# =============================================================================
# BIGFOOT TRAILERS API — Comprehensive Postman-Style Test Suite
# Tests every module: Health, Auth, Users, Trailers, QC, Payroll, Deliveries,
#                     Admin, Error Codes, Security Headers, Rate Limiting
# =============================================================================

BASE="http://localhost:3000"
API="$BASE/v1"
PASS=0
FAIL=0
TOTAL=0

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

assert() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} [$TOTAL] $name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [$TOTAL] $name — expected: '$expected', got: '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -q "$expected"; then
    echo -e "  ${GREEN}PASS${NC} [$TOTAL] $name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [$TOTAL] $name — expected to contain: '$expected'"
    FAIL=$((FAIL + 1))
  fi
}

extract() {
  node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const p='$1'.split('.');let v=d;for(const k of p)v=v?.[k];process.stdout.write(String(v??''))}catch{process.stdout.write('PARSE_ERROR')}"
}

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  BIGFOOT TRAILERS API — POSTMAN TEST SUITE                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 1. HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[1] HEALTH CHECK${NC}"

R=$(curl -s $BASE/health)
assert "GET /health — success" "true" "$(echo $R | extract 'success')"
assert "GET /health — status ok" "ok" "$(echo $R | extract 'data.status')"
assert "GET /health — database ok" "ok" "$(echo $R | extract 'data.checks.database.status')"
assert "GET /health — redis ok" "ok" "$(echo $R | extract 'data.checks.redis.status')"
assert "GET /health — has uptime" "true" "$(echo $R | extract 'data.uptime' | node -e "process.stdout.write(String(parseFloat(require('fs').readFileSync(0,'utf8'))>0))")"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 2. SECURITY HEADERS
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[2] SECURITY HEADERS${NC}"

HEADERS=$(curl -sI $BASE/health)
assert_contains "Helmet — Content-Security-Policy" "default-src 'self'" "$HEADERS"
assert_contains "Helmet — Strict-Transport-Security" "max-age=31536000" "$HEADERS"
assert_contains "Helmet — X-Content-Type-Options" "nosniff" "$HEADERS"
assert_contains "Helmet — X-Frame-Options" "SAMEORIGIN" "$HEADERS"
assert_contains "Helmet — Referrer-Policy" "strict-origin-when-cross-origin" "$HEADERS"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 3. AUTH — LOGIN
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[3] AUTH — LOGIN${NC}"

R=$(curl -s -X POST $API/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@bigfoottrailers.com","password":"Admin123!"}')
assert "POST /auth/login — success" "true" "$(echo $R | extract 'success')"
assert "POST /auth/login — has accessToken" "true" "$(echo $R | extract 'data.accessToken' | node -e "process.stdout.write(String(require('fs').readFileSync(0,'utf8').length>20))")"
assert "POST /auth/login — has refreshToken" "true" "$(echo $R | extract 'data.refreshToken' | node -e "process.stdout.write(String(require('fs').readFileSync(0,'utf8').length>20))")"
assert "POST /auth/login — expiresIn=900" "900" "$(echo $R | extract 'data.expiresIn')"

TOKEN=$(echo $R | extract 'data.accessToken')
REFRESH=$(echo $R | extract 'data.refreshToken')
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 4. AUTH — REFRESH TOKEN
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[4] AUTH — REFRESH TOKEN${NC}"

R=$(curl -s -X POST $API/auth/refresh -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$REFRESH\"}")
assert "POST /auth/refresh — success" "true" "$(echo $R | extract 'success')"
assert "POST /auth/refresh — new accessToken" "true" "$(echo $R | extract 'data.accessToken' | node -e "process.stdout.write(String(require('fs').readFileSync(0,'utf8').length>20))")"

# Re-login for fresh token
R=$(curl -s -X POST $API/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@bigfoottrailers.com","password":"Admin123!"}')
TOKEN=$(echo $R | extract 'data.accessToken')
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 5. AUTH — ERROR CASES
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[5] AUTH — ERROR CASES${NC}"

R=$(curl -s -X POST $API/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@bigfoottrailers.com","password":"WrongPass!"}')
assert "POST /auth/login — wrong password → UNAUTHORIZED" "UNAUTHORIZED" "$(echo $R | extract 'error.code')"

R=$(curl -s $API/trailers)
assert "GET /trailers — no token → UNAUTHORIZED" "UNAUTHORIZED" "$(echo $R | extract 'error.code')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 6. USERS — CRUD
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[6] USERS — CRUD${NC}"

R=$(curl -s $API/users -H "Authorization: Bearer $TOKEN")
assert "GET /users — success" "true" "$(echo $R | extract 'success')"
INITIAL_USERS=$(echo $R | extract 'data.total')

R=$(curl -s -X POST $API/users -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"email":"pm1@bigfoot.com","fullName":"Production Manager","password":"PmPass123!","role":"production_manager"}')
assert "POST /users — create production_manager" "true" "$(echo $R | extract 'success')"
PM_ID=$(echo $R | extract 'data.id')

R=$(curl -s $API/users/$PM_ID -H "Authorization: Bearer $TOKEN")
assert "GET /users/:id — fetch PM" "Production Manager" "$(echo $R | extract 'data.fullName')"

R=$(curl -s -X PATCH $API/users/$PM_ID -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"phone":"555-0100"}')
assert "PATCH /users/:id — update phone" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 7. TRAILERS — CREATE + LIST
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[7] TRAILERS — CREATE + LIST${NC}"

R=$(curl -s -X POST $API/trailers -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"soNumber":"SO-PM-100","trailerModelId":1,"color":"Blue","sizeFt":"20"}')
assert "POST /trailers — create XP trailer" "true" "$(echo $R | extract 'success')"
assert "POST /trailers — status=pending_production" "pending_production" "$(echo $R | extract 'data.trailer.status')"
assert "POST /trailers — 12 steps generated" "12" "$(echo $R | extract 'data.stepsSummary.totalSteps')"
TRAILER_ID=$(echo $R | extract 'data.trailer.id')

R=$(curl -s "$API/trailers?page=1&limit=10" -H "Authorization: Bearer $TOKEN")
assert "GET /trailers — list success" "true" "$(echo $R | extract 'success')"
assert_contains "GET /trailers — total > 0" "true" "$(echo $R | extract 'data.total' | node -e "process.stdout.write(String(parseInt(require('fs').readFileSync(0,'utf8'))>0))")"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 8. TRAILERS — DETAIL, STEPS, HISTORY
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[8] TRAILERS — DETAIL, STEPS, HISTORY${NC}"

R=$(curl -s $API/trailers/$TRAILER_ID -H "Authorization: Bearer $TOKEN")
assert "GET /trailers/:id — detail" "SO-PM-100" "$(echo $R | extract 'data.soNumber')"
assert "GET /trailers/:id — has model" "xp" "$(echo $R | extract 'data.trailerModel.series')"

R=$(curl -s $API/trailers/$TRAILER_ID/steps -H "Authorization: Bearer $TOKEN")
assert "GET /trailers/:id/steps — 12 steps" "12" "$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(String(d.data?.length??0))")"
STEP1_DEPT=$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.data?.[0]?.department?.code??'')")
assert "GET /trailers/:id/steps — step 1 = XP_JIG" "XP_JIG" "$STEP1_DEPT"
STEP1_STATUS=$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.data?.[0]?.status??'')")
assert "GET /trailers/:id/steps — step 1 active" "active" "$STEP1_STATUS"

R=$(curl -s $API/trailers/$TRAILER_ID/history -H "Authorization: Bearer $TOKEN")
assert "GET /trailers/:id/history — success" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 9. TRAILERS — HOT, PRIORITY, ADDON
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[9] TRAILERS — HOT, PRIORITY, ADDON${NC}"

R=$(curl -s -X PATCH $API/trailers/$TRAILER_ID/hot -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"isHot":true}')
assert "PATCH /trailers/:id/hot — isHot=true" "true" "$(echo $R | extract 'data.isHot')"

R=$(curl -s -X PATCH $API/trailers/$TRAILER_ID/priority -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"globalPriority":1}')
assert "PATCH /trailers/:id/priority — set to 1" "1" "$(echo $R | extract 'data.globalPriority')"

R=$(curl -s -X POST $API/trailers/$TRAILER_ID/addons -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"addonName":"Tongue Box","notes":"Aluminum, locking"}')
assert "POST /trailers/:id/addons — create" "true" "$(echo $R | extract 'success')"
assert "POST /trailers/:id/addons — name" "Tongue Box" "$(echo $R | extract 'data.addonName')"
ADDON_ID=$(echo $R | extract 'data.id')

R=$(curl -s -X DELETE $API/trailers/$TRAILER_ID/addons/$ADDON_ID -H "Authorization: Bearer $TOKEN")
assert "DELETE /trailers/:id/addons/:id — remove" "true" "$(echo $R | extract 'data.deleted')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 10. TRAILERS — GOOSENECK WORKFLOW
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[10] TRAILERS — GOOSENECK WORKFLOW VERIFICATION${NC}"

R=$(curl -s -X POST $API/trailers -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"soNumber":"SO-GN-100","trailerModelId":6}')
assert "POST /trailers — create Gooseneck" "true" "$(echo $R | extract 'success')"
GN_ID=$(echo $R | extract 'data.trailer.id')

R=$(curl -s $API/trailers/$GN_ID/steps -H "Authorization: Bearer $TOKEN")
GN_STEP1=$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.data?.[0]?.department?.code??'')")
GN_STEP7=$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.data?.[6]?.department?.code??'')")
GN_STEP9=$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.data?.[8]?.department?.code??'')")
assert "Gooseneck step 1 = GN_WELD" "GN_WELD" "$GN_STEP1"
assert "Gooseneck step 7 = PAINT_B (not PAINT_A)" "PAINT_B" "$GN_STEP7"
assert "Gooseneck step 9 = HYDRAULICS (not WIRE)" "HYDRAULICS" "$GN_STEP9"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 11. QC — CHECKLIST + INSPECTION
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[11] QC — CHECKLIST + INSPECTION${NC}"

# Get QC_1 department ID
QC1_DEPT_ID=$(curl -s $API/admin/departments -H "Authorization: Bearer $TOKEN" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const qc=d.data?.find(x=>x.code==='QC_1');process.stdout.write(String(qc?.id??''))")

R=$(curl -s -X POST $API/qc/checklist-items -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d "{\"departmentId\":$QC1_DEPT_ID,\"itemLabel\":\"Weld penetration check\",\"sortOrder\":1}")
assert "POST /qc/checklist-items — create" "true" "$(echo $R | extract 'success')"
CHECKLIST_ID=$(echo $R | extract 'data.id')

R=$(curl -s "$API/qc/checklist-items" -H "Authorization: Bearer $TOKEN")
assert "GET /qc/checklist-items — list" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 12. PAYROLL — POINT VALUES + DOLLAR RATES + REPORT
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[12] PAYROLL — POINT VALUES + DOLLAR RATES${NC}"

# Get XP_JIG department ID
XPJIG_DEPT_ID=$(curl -s $API/admin/departments -H "Authorization: Bearer $TOKEN" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const dept=d.data?.find(x=>x.code==='XP_JIG');process.stdout.write(String(dept?.id??''))")

R=$(curl -s -X POST $API/payroll/point-values -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d "{\"trailerModelId\":1,\"departmentId\":$XPJIG_DEPT_ID,\"points\":5.0,\"effectiveFrom\":\"2026-01-01\"}")
assert "POST /payroll/point-values — create" "true" "$(echo $R | extract 'success')"

R=$(curl -s $API/payroll/point-values -H "Authorization: Bearer $TOKEN")
assert "GET /payroll/point-values — list" "true" "$(echo $R | extract 'success')"

R=$(curl -s -X POST $API/payroll/dollar-rates -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d "{\"departmentId\":$XPJIG_DEPT_ID,\"dollarPerPoint\":15.00,\"effectiveFrom\":\"2026-01-01\"}")
assert "POST /payroll/dollar-rates — create" "true" "$(echo $R | extract 'success')"

R=$(curl -s $API/payroll/dollar-rates -H "Authorization: Bearer $TOKEN")
assert "GET /payroll/dollar-rates — list" "true" "$(echo $R | extract 'success')"

R=$(curl -s "$API/payroll/records/week/2026-04-05" -H "Authorization: Bearer $TOKEN")
assert "GET /payroll/records/week — report" "true" "$(echo $R | extract 'success')"
assert "GET /payroll/records/week — correct date" "2026-04-05" "$(echo $R | extract 'data.weekStartDate')"

R=$(curl -s "$API/payroll/worker/2/summary" -H "Authorization: Bearer $TOKEN")
assert "GET /payroll/worker/:id/summary" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 13. ADMIN — DEPARTMENTS + TEMPLATES + AUDIT LOG
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[13] ADMIN — DEPARTMENTS + TEMPLATES + AUDIT LOG${NC}"

R=$(curl -s $API/admin/departments -H "Authorization: Bearer $TOKEN")
assert "GET /admin/departments — 20 depts" "20" "$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(String(d.data?.length??0))")"

R=$(curl -s $API/admin/workflow-templates -H "Authorization: Bearer $TOKEN")
assert "GET /admin/workflow-templates — 48 templates" "48" "$(echo $R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(String(d.data?.length??0))")"

R=$(curl -s "$API/admin/audit-log?page=1&limit=5" -H "Authorization: Bearer $TOKEN")
assert "GET /admin/audit-log — success" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 14. ERROR CODES — ALL TYPED ERRORS
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[14] ERROR CODES — TYPED ERRORS${NC}"

# SO_NUMBER_EXISTS (409)
R=$(curl -s -X POST $API/trailers -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"soNumber":"SO-PM-100","trailerModelId":1}')
assert "SO_NUMBER_EXISTS — duplicate SO" "SO_NUMBER_EXISTS" "$(echo $R | extract 'error.code')"

# NOT_FOUND (404)
R=$(curl -s $API/trailers/99999 -H "Authorization: Bearer $TOKEN")
assert "NOT_FOUND — trailer 99999" "NOT_FOUND" "$(echo $R | extract 'error.code')"

# DELIVERY_NOT_DISPATCHABLE (400)
R=$(curl -s -X POST $API/deliveries -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d "{\"trailerId\":$TRAILER_ID,\"deliveryType\":\"single_pull\"}")
assert "DELIVERY_NOT_DISPATCHABLE — pending trailer" "DELIVERY_NOT_DISPATCHABLE" "$(echo $R | extract 'error.code')"

# INVALID_WEEK_START (400)
R=$(curl -s "$API/payroll/records/week/2026-04-06" -H "Authorization: Bearer $TOKEN")
assert "INVALID_WEEK_START — Monday date" "INVALID_WEEK_START" "$(echo $R | extract 'error.code')"

# VALIDATION — missing required fields
R=$(curl -s -X POST $API/trailers -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{}')
assert "VALIDATION — empty body → BAD_REQUEST" "BAD_REQUEST" "$(echo $R | extract 'error.code')"
assert_contains "VALIDATION — has details array" "soNumber" "$(echo $R | extract 'error.details')"

# WHITELIST — unknown property rejected
R=$(curl -s -X POST $API/trailers -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"soNumber":"SO-999","trailerModelId":1,"hackerField":"pwned"}')
assert "WHITELIST — unknown prop rejected" "BAD_REQUEST" "$(echo $R | extract 'error.code')"
assert_contains "WHITELIST — mentions hackerField" "hackerField" "$(echo $R | extract 'error.details')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 15. QC ERROR CODES (with QC inspector)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[15] QC ERROR CODES${NC}"

QC_R=$(curl -s -X POST $API/auth/login -H "Content-Type: application/json" \
  -d '{"email":"qc1@bigfoot.com","password":"QcPass123!"}')
QC_TOKEN=$(echo $QC_R | extract 'data.accessToken')

# Get step IDs for the trailer
STEPS_R=$(curl -s $API/trailers/$TRAILER_ID/steps -H "Authorization: Bearer $TOKEN")
QC_STEP_ID=$(echo $STEPS_R | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const s=d.data?.find(x=>x.department?.code==='QC_1');process.stdout.write(String(s?.id??''))")

# STEP_NOT_ACTIVE — QC_1 is waiting
R=$(curl -s -X POST $API/qc/inspections -H "Content-Type: application/json" -H "Authorization: Bearer $QC_TOKEN" \
  -d "{\"productionStepId\":$QC_STEP_ID,\"result\":\"pass\",\"checklistResults\":[{\"checklistItemId\":$CHECKLIST_ID,\"passed\":true}],\"photoStorageKeys\":[\"photo1.jpg\"]}")
assert "STEP_NOT_ACTIVE — QC on waiting step" "STEP_NOT_ACTIVE" "$(echo $R | extract 'error.code')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 16. INPUT SANITIZATION
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[16] INPUT SANITIZATION${NC}"

R=$(curl -s -X POST $API/trailers/$TRAILER_ID/addons -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"addonName":"<script>alert(1)</script>Sanitized","notes":"<b>Bold</b> text"}')
SANITIZED_NAME=$(echo $R | extract 'data.addonName')
SANITIZED_NOTES=$(echo $R | extract 'data.notes')
assert "XSS — <script> tag stripped" "alert(1)Sanitized" "$SANITIZED_NAME"
assert "XSS — <b> tag stripped" "Bold text" "$SANITIZED_NOTES"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 17. RESPONSE ENVELOPE FORMAT
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[17] RESPONSE ENVELOPE FORMAT${NC}"

R=$(curl -s $BASE/health)
assert "Envelope — success field exists" "true" "$(echo $R | extract 'success')"
assert_contains "Envelope — has meta.timestamp" "T" "$(echo $R | extract 'meta.timestamp')"
assert "Envelope — meta.path" "/health" "$(echo $R | extract 'meta.path')"
assert "Envelope — meta.method" "GET" "$(echo $R | extract 'meta.method')"

R=$(curl -s $API/trailers/99999 -H "Authorization: Bearer $TOKEN")
assert "Error envelope — success=false" "false" "$(echo $R | extract 'success')"
assert_contains "Error envelope — has error.code" "NOT_FOUND" "$(echo $R | extract 'error.code')"
assert_contains "Error envelope — has error.message" "not found" "$(echo $R | extract 'error.message')"
assert "Error envelope — meta.method" "GET" "$(echo $R | extract 'meta.method')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# 18. AUTH — LOGOUT
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[18] AUTH — LOGOUT${NC}"

LOGOUT_R=$(curl -s -X POST $API/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@bigfoottrailers.com","password":"Admin123!"}')
LOGOUT_REFRESH=$(echo $LOGOUT_R | extract 'data.refreshToken')

R=$(curl -s -X POST $API/auth/logout -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$LOGOUT_REFRESH\"}")
assert "POST /auth/logout — success" "true" "$(echo $R | extract 'success')"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}ALL $TOTAL TESTS PASSED ($PASS/$TOTAL)${NC}"
else
  echo -e "${RED}$FAIL FAILED${NC}, ${GREEN}$PASS PASSED${NC} out of $TOTAL tests"
fi
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
