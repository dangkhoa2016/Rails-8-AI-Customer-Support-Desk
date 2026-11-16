#!/usr/bin/env python3
"""Prepare human-reviewable v2 drafts for six high-risk KB articles.
Never changes canonical M0 policy JSON or approves articles.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDS = ["TF-KB-012", "TF-KB-015", "NM-KB-014", "NM-KB-020", "NM-KB-029", "NM-KB-030"]
CLARS = {
    "TF-KB-012": ["M0-CLAR-001", "M0-CLAR-002"],
    "TF-KB-015": ["M0-CLAR-003"],
    "NM-KB-014": ["M0-CLAR-008"],
    "NM-KB-020": [],
    "NM-KB-029": ["M0-CLAR-004"],
    "NM-KB-030": ["M0-CLAR-004", "M0-CLAR-005"],
}
# Fields are independently authored in each language. They are editorial
# proposals, not human-approved customer-facing knowledge.
DETAILS = {
 "TF-KB-012": {
   "vi": {
     "scope": "Áp dụng khi khách hàng nói đã thanh toán để mở gói trả phí nhưng workspace vẫn hiển thị quyền của gói cũ. Không suy ra tình trạng kích hoạt chỉ từ ảnh biên nhận hoặc lời khách.",
     "evidence": "Xác minh đúng tổ chức, khách hàng và workspace; lấy invoice liên quan, trạng thái paid, activation event khớp invoice và effective_plan từ read-only records. requested_plan chỉ phản ánh gói đã yêu cầu. Ghi nhận thông tin còn thiếu thay vì suy diễn.",
     "steps": "1. Nếu invoice chưa paid, không xác nhận quyền gói trả phí. 2. Nếu paid nhưng activation failed/chưa có succeeded event khớp, giữ nguyên effective_plan đã xác minh và chuyển xử lý kích hoạt. 3. Chỉ mô tả gói mới đã có hiệu lực khi có đồng thời invoice paid, activation succeeded và effective_plan phù hợp. 4. Không tự sửa subscription hay kích hoạt lại bằng AI.",
     "example": "“Chúng tôi đã ghi nhận trạng thái thanh toán của hóa đơn được xác minh, nhưng chưa có bằng chứng gói mới đã kích hoạt thành công. Quyền truy cập hiện tại được xác định theo gói có hiệu lực trong hệ thống. Tôi sẽ chuyển trường hợp này cho nhân viên xử lý; chưa thể xác nhận thời điểm hoàn tất.”",
     "escalate": "Chuyển nhân viên có quyền khi event thất bại, không khớp invoice, dữ liệu xung đột hoặc khách yêu cầu khắc phục quyền truy cập. Không công bố hóa đơn/workspace của tenant khác; không hứa hoàn tiền hoặc ngày xử lý khi chưa có quyết định."
   },
   "en": {
     "scope": "Use this article when a customer reports paying for a paid plan while the workspace still shows older entitlements. A receipt screenshot or customer assertion does not establish activation.",
     "evidence": "Verify the authorized organization, customer and workspace; check the relevant invoice and its paid state, the matching activation event, and the read-only effective_plan. requested_plan indicates only the requested change. Record missing evidence rather than guessing.",
     "steps": "1. If the invoice is not paid, do not confirm paid entitlements. 2. If paid but activation failed or no matching succeeded event exists, retain the verified effective_plan and escalate activation. 3. Say the new plan is live only when invoice paid, matching activation succeeded, and effective_plan agree. 4. AI must not change subscriptions or retry activation.",
     "example": "“We can confirm the verified invoice payment, but we cannot yet verify that the new plan was activated successfully. The current access level follows the effective plan recorded by the system. I will escalate this for an authorized agent to investigate, without promising a completion time.”",
     "escalate": "Escalate failed, missing or conflicting activation events and requests to restore entitlements. Do not expose another tenant's invoices/workspaces, promise refunds, or commit to a resolution deadline without authorization."
   }
 },
 "TF-KB-015": {
   "vi": {
     "scope": "Áp dụng cho yêu cầu hoàn tiền liên quan hóa đơn paid đầu tiên của TeamFlow Cloud. Đây là điều kiện được đưa vào xem xét thủ công, không phải quyền được hoàn tiền tự động.",
     "evidence": "Xác minh workspace và khách hàng đúng tenant, tìm hóa đơn paid đầu tiên và ngày paid theo múi giờ Asia/Ho_Chi_Minh, ngày tiếp nhận yêu cầu và tình trạng thanh toán. Không tính từ invoice pending/failed hoặc từ ngày ticket được tạo nếu khác ngày yêu cầu.",
     "steps": "1. Lấy ngày paid đầu tiên làm ngày 0 theo lịch địa phương. 2. Ngày 0 đến hết ngày 7: chuyển xem xét thủ công theo chính sách. 3. Từ ngày 8: chuyển xét ngoại lệ, không nói chắc sẽ được duyệt. 4. Việc gửi yêu cầu không thay đổi subscription; AI không hoàn tiền hoặc hủy gói.",
     "example": "“Theo ngày thanh toán đầu tiên và ngày gửi yêu cầu đã được xác minh, yêu cầu của bạn thuộc diện [xem xét thủ công trong hạn / chuyển xét ngoại lệ]. Kết quả hoàn tiền chưa được phê duyệt; nhân viên có thẩm quyền sẽ đánh giá và phản hồi.”",
     "escalate": "Chuyển owner/admin hoặc nhân viên được phân quyền xử lý billing. Không nêu thời gian hoàn tiền, số tiền được hoàn hoặc kết quả chấp thuận khi chưa có quyết định và bản ghi hợp lệ."
   },
   "en": {
     "scope": "Use this article for a refund request tied to the first paid TeamFlow Cloud invoice. The policy establishes eligibility for human consideration, not an automatic refund entitlement.",
     "evidence": "Verify the tenant, customer and workspace; locate the first paid invoice and its payment date in Asia/Ho_Chi_Minh local calendar time; confirm the request submission date. Do not count pending/failed invoices or substitute ticket creation dates for the actual request date.",
     "steps": "1. Count the first paid date as calendar day 0. 2. Days 0–7 inclusive: route for manual review. 3. From day 8: route for exception consideration without promising approval. 4. Filing a request does not change the subscription; AI never executes refunds or cancellation.",
     "example": "“Based on the verified first payment and request dates, this request is [within the manual-review window / outside the standard window and requires exception review]. A refund has not been approved. An authorized team member will assess the request.”",
     "escalate": "Refer billing decisions to authorized staff. Never promise the refunded amount, processing time, subscription change, or approval outcome without a corresponding authorized decision."
   }
 },
 "NM-KB-014": {
   "vi": {
     "scope": "Dùng khi khách hỏi vì sao đơn NovaMart Store có hoặc không có phí vận chuyển thường. Ngưỡng miễn phí dựa trên giá trị hàng hóa sau giảm giá, không bao gồm phí giao hàng.",
     "evidence": "Chỉ đọc các order items đúng đơn hàng/khách hàng và lấy quantity, unit_price_snapshot_vnd, discount_snapshot_vnd đã lưu. Kiểm tra loại phí vận chuyển; chính sách này áp dụng cho phí vận chuyển thường trong demo, không mặc định cho dịch vụ khác.",
     "steps": "1. subtotal_vnd = tổng quantity × unit_price_snapshot_vnd. 2. discount_vnd = tổng discount_snapshot_vnd. 3. net_merchandise_vnd = subtotal_vnd − discount_vnd. 4. Nếu net_merchandise_vnd < 500.000 VND, standard_shipping_vnd = 30.000 VND; nếu >= 500.000 thì bằng 0. 5. grand_total_vnd = net_merchandise_vnd + shipping_vnd. Tính bằng số nguyên VND, không cộng shipping vào phép so ngưỡng.",
     "example": "“Nếu tổng hàng sau giảm giá là 499.999 VND, phí giao thường là 30.000 VND, tổng 529.999 VND. Nếu đúng 500.000 VND thì phí giao thường là 0 VND, tổng 500.000 VND.” Đây là ví dụ chính sách, không phải báo giá của đơn khách nếu chưa tra cứu.",
     "escalate": "Chuyển nhân viên nếu snapshot đơn hoặc phí ghi nhận không khớp công thức, thiếu dữ liệu hoặc có yêu cầu miễn/hoàn phí ngoại lệ. Không tự sửa giá, snapshot hoặc phí vận chuyển."
   },
   "en": {
     "scope": "Use this article to explain NovaMart Store standard shipping fees. The free-shipping threshold is based on merchandise value after discounts; shipping itself does not count toward the threshold.",
     "evidence": "Read only authorized order item records and their stored quantity, unit_price_snapshot_vnd and discount_snapshot_vnd. Check whether the charge is standard shipping; these rules do not establish prices for unlisted delivery services.",
     "steps": "1. subtotal_vnd = sum(quantity × unit_price_snapshot_vnd). 2. discount_vnd = sum(discount_snapshot_vnd). 3. net_merchandise_vnd = subtotal_vnd − discount_vnd. 4. If net_merchandise_vnd is below VND 500,000, standard shipping is VND 30,000; at or above the threshold it is VND 0. 5. grand_total_vnd = net_merchandise_vnd + shipping_vnd. Use integer VND, excluding shipping from threshold tests.",
     "example": "“At VND 499,999 after discounts, standard shipping is VND 30,000 and the total is VND 529,999. At exactly VND 500,000, standard shipping is VND 0 and the total is VND 500,000.” This illustrates policy, not a verified customer's order amount.",
     "escalate": "Escalate mismatched snapshots/fees, missing records, or requests for fee waivers/refunds. AI must not change item snapshots, prices, or shipping charges."
   }
 },
 "NM-KB-020": {
   "vi": {
     "scope": "Áp dụng khi khách hỏi ngày dự kiến nhận đơn đã thanh toán. Cần phân biệt thời gian mục tiêu bàn giao hãng vận chuyển và thời gian dự kiến giao sau bàn giao; cả hai không phải cam kết chắc chắn.",
     "evidence": "Kiểm tra payment paid, ngày giờ carrier handoff đã được xác minh và trạng thái shipment trong đúng đơn/tenant. Nếu đơn tách nhiều kiện, xem từng shipment; không coi label_created là đã bàn giao. Không lấy lời khách thay thế tracking có thẩm quyền.",
     "steps": "1. Sau paid, mục tiêu bàn giao carrier là trong 2 ngày làm việc (không tính ngày nghỉ cuối tuần; demo chưa xét ngày lễ). 2. Khi đã có bằng chứng bàn giao, thời gian giao dự kiến là 2–5 ngày làm việc sau thời điểm bàn giao. 3. Nếu chưa bàn giao thì không được tự suy ra một ngày giao chính xác. 4. Nếu tracking exception hoặc thiếu cập nhật, chuyển nhân viên kiểm tra với đối tác vận chuyển.",
     "example": "“Theo chính sách, cửa hàng đặt mục tiêu bàn giao đơn cho hãng vận chuyển trong 2 ngày làm việc sau khi thanh toán. Sau khi bàn giao, thời gian giao dự kiến là 2–5 ngày làm việc; đây không phải ngày giao bảo đảm. Tôi cần kiểm tra bản ghi vận chuyển của đơn để báo tình trạng cụ thể.”",
     "escalate": "Chuyển khi thiếu bàn giao quá mục tiêu, tracking exception, giao thiếu kiện hoặc khách yêu cầu cam kết thời điểm giao. Không tự tạo tracking, hứa bồi thường hay tái gửi hàng."
   },
   "en": {
     "scope": "Use this article for questions about expected delivery of a paid NovaMart Store order. Distinguish the carrier handoff target from the subsequent delivery estimate; neither is a guaranteed delivery date.",
     "evidence": "Verify payment marked paid, confirmed carrier handoff time, and tenant-scoped shipment records. For partial shipments, inspect each shipment individually; label_created alone does not prove handoff. Customer text is not authoritative tracking data.",
     "steps": "1. After paid status, the carrier handoff target is within 2 business days (weekdays for the demo; holidays are not modeled). 2. Once handoff is evidenced, the delivery estimate is 2–5 business days afterward. 3. Before handoff, do not invent a precise delivery date. 4. Escalate shipment exceptions or missing tracking updates for human investigation.",
     "example": "“Our policy targets carrier handoff within two business days after payment. Once handed over, delivery is estimated at two to five business days, not guaranteed. We need to verify your order's shipment record before giving a case-specific update.”",
     "escalate": "Escalate missed handoff targets, tracking exceptions, partial deliveries and requests for guaranteed arrival. AI must not fabricate tracking, compensation, or replacement shipments."
   }
 },
 "NM-KB-029": {
   "vi": {
     "scope": "Quy trình tiếp nhận yêu cầu đổi/trả thông thường cho hàng chưa sử dụng, còn bao bì gốc. Không dùng cửa sổ này để từ chối báo thiếu/sai/hỏng/lỗi trong 14 ngày hoặc yêu cầu bảo hành.",
     "evidence": "Xác minh order/item, đúng khách hàng, ngày delivered của chính item đó, tình trạng chưa dùng và bao bì gốc. Với giao nhiều kiện, không lấy ngày giao kiện khác hoặc ngày shipped để tính hạn.",
     "steps": "1. Xác định ngày delivered đã xác nhận theo lịch Asia/Ho_Chi_Minh (ngày giao là ngày 0). 2. Ngày 0–7: có thể tiếp nhận và chuyển người có thẩm quyền đánh giá điều kiện hàng. 3. Từ ngày 8: ngoài cửa sổ tiêu chuẩn, chuyển xem xét riêng, không tự từ chối mọi quyền lợi khác. 4. Yêu cầu không đồng nghĩa đổi/trả hoặc hoàn tiền đã được duyệt.",
     "example": "“Nếu mặt hàng được xác nhận giao ngày 1, yêu cầu đổi/trả thông thường gửi đến hết ngày 8 (ngày thứ 7) vẫn trong cửa sổ xem xét; gửi ngày 9 (ngày thứ 8) nằm ngoài cửa sổ tiêu chuẩn. Việc chấp thuận vẫn cần kiểm tra tình trạng hàng và phê duyệt.”",
     "escalate": "Chuyển nhân viên khi ngày giao chưa xác minh, hàng đã dùng/thiếu bao bì, yêu cầu quá hạn hoặc liên quan hàng lỗi/thiếu/sai. AI không quyết định hoàn tiền, thay hàng hay cập nhật đơn."
   },
   "en": {
     "scope": "This describes ordinary return requests for unused goods with original packaging. The seven-day window must not be used to reject separate defect, damage, missing or wrong-item reports or warranty inquiries.",
     "evidence": "Verify the authorized order/customer, the confirmed delivered date of the relevant item, unused condition and original packaging. For split shipments, do not use the date of a different package or the shipped date.",
     "steps": "1. Use the item's confirmed delivery date in the Asia/Ho_Chi_Minh local calendar (delivery day is day 0). 2. Days 0–7 inclusive: request may be considered after condition checks and human review. 3. From day 8: outside the standard ordinary-return window, route for separate assessment rather than rejecting every other possible remedy. 4. A request is not an approved return or refund.",
     "example": "“If an item was confirmed delivered on the 1st, an ordinary return request made by the 8th (day 7) falls within the review window. A request on the 9th (day 8) is outside the standard window. Approval still depends on condition verification and human authorization.”",
     "escalate": "Escalate missing delivery evidence, used goods, missing original packaging, out-of-window requests or reports of defective/missing/wrong goods. AI never authorizes returns, replacements or refunds."
   }
 },
 "NM-KB-030": {
   "vi": {
     "scope": "Dành cho việc báo hàng lỗi, hỏng, thiếu hoặc giao sai trong vòng 14 ngày lịch từ ngày item được xác nhận giao. Cửa sổ này độc lập với đổi/trả thông thường 7 ngày và thời hạn bảo hành theo SKU.",
     "evidence": "Xác minh đơn và item đúng tenant, ngày delivered của từng item, loại vấn đề, ảnh/chứng cứ phù hợp và trạng thái các kiện hàng. Với báo thiếu, kiểm tra partial shipment trước khi kết luận thiếu hàng. Xác minh warranty_months của SKU nếu hỏi bảo hành.",
     "steps": "1. Đếm ngày lịch địa phương, ngày delivered là ngày 0. 2. Ngày 0–14: tiếp nhận báo lỗi và chuyển xác minh; ngày 14 vẫn trong cửa sổ. 3. Ngày 15: ngoài cửa sổ báo lỗi chuẩn, nhưng có thể kiểm tra bảo hành riêng theo warranty_months và ngày delivered. 4. Không suy ra lỗi được chấp nhận, hoàn tiền hay đổi mới chỉ từ ảnh khách gửi.",
     "example": "“Yêu cầu báo lỗi ở ngày thứ 14 kể từ ngày giao đã xác minh vẫn nằm trong thời hạn 14 ngày để được xem xét. Từ ngày thứ 15, cửa sổ báo lỗi tiêu chuẩn kết thúc; chúng tôi cần kiểm tra điều kiện bảo hành của đúng SKU để xác định hướng xử lý khác, không thể hứa kết quả.”",
     "escalate": "Chuyển nhân viên để xác minh hỏng/thiếu/sai hàng, chứng cứ xung đột hoặc bảo hành. AI không tạo quyết định refund, replacement hoặc warranty claim đã được duyệt."
   },
   "en": {
     "scope": "Use this article for defective, damaged, missing or wrong-item reports within 14 local calendar days of confirmed item delivery. This window is separate from seven-day ordinary returns and the SKU-specific warranty period.",
     "evidence": "Verify the correct tenant, order and item; each item's confirmed delivered date, issue type, appropriate photos/evidence and split-shipment status. For missing goods, check partial shipments before concluding an item was lost. Verify SKU warranty_months separately if warranty is requested.",
     "steps": "1. Count local calendar days from the confirmed item delivery date, with delivery as day 0. 2. Days 0–14 inclusive: accept the report for verification; day 14 is still within the window. 3. Day 15 is outside the standard defect-report window, but SKU warranty may still apply independently according to warranty_months and verified delivery date. 4. Customer photos alone do not authorize refund or replacement.",
     "example": "“A defect report submitted on day 14 after verified delivery is within the 14-day reporting window and requires review. From day 15, the standard report window has passed; we can separately check the specific SKU warranty without promising an outcome.”",
     "escalate": "Escalate verification of defective, damaged, missing or wrong items, conflicting evidence, and warranty assessment. AI must not approve refunds, replacements or warranty claims."
   }
 }
}

def sha(s): return hashlib.sha256(s.encode('utf-8')).hexdigest()

def build():
  blueprint_path = ROOT / 'data/policy/canonical_blueprint.json'
  canonical = json.loads(blueprint_path.read_text(encoding='utf-8'))
  kb_path = ROOT / 'data/m2/knowledge_drafts.json'
  kb = json.loads(kb_path.read_text(encoding='utf-8'))
  rule_map = {r['id']: r for org in canonical['organizations'] for r in org['rules']}
  clar_map = {r['id']: r for r in canonical['implementation_clarifications']}
  source = {a['article_key']: a for a in kb['articles']}
  revisions = []
  for key in IDS:
    a = source[key]
    policy_ids = a['policy_refs'] + CLARS[key]
    for v in a['versions']:
      lang = v['locale']
      note = DETAILS[key][lang]
      heads = ('Phạm vi', 'Chính sách có hiệu lực', 'Chứng cứ cần xác minh', 'Các bước xử lý', 'Câu trả lời mẫu có điều kiện', 'Khi cần chuyển cấp') if lang == 'vi' else (
          'Scope', 'Authoritative policy', 'Evidence to verify', 'Handling steps', 'Conditional response example', 'When to escalate')
      policy_lines = []
      for ref in policy_ids:
        entry = rule_map.get(ref) or clar_map.get(ref)
        assert entry, ref
        policy_lines.append(f"- **{ref}** — {entry[lang]}")
      values = [note['scope'], '\n'.join(policy_lines), note['evidence'], note['steps'], note['example'], note['escalate']]
      sections = [f"# {v['title']}\n\n"]
      sections += [f"## {heading}\n{body}\n\n" for heading, body in zip(heads, values)]
      assert len(sections) == 7
      body = ''.join(sections)
      revisions.append({
        'organization_slug': a['organization_slug'], 'article_key': key,
        'locale': lang, 'version': 2, 'title': v['title'], 'body': body,
        'sha256': sha(body), 'chunks': [{'chunk_index': i, 'body': text, 'sha256': sha(text)} for i, text in enumerate(sections)],
        'status': 'draft', 'approved_by': None, 'approved_at': None,
        'effective_from': v['effective_from'], 'effective_to': v.get('effective_to'),
        'based_on_v1_sha256': v['sha256'], 'policy_refs': a['policy_refs'],
        'clarification_refs': CLARS[key], 'editorial_decision': 'PENDING_HUMAN_REVIEW',
      })
  assert len(revisions) == 12
  payload = {
    'kind': 'M2_HIGH_PRIORITY_EDITORIAL_PROPOSALS_NOT_APPROVED',
    'seed': kb['seed'], 'policy_version': kb['policy_version'],
    'canonical_sha256': sha(blueprint_path.read_text(encoding='utf-8')),
    'source_m2_sha256': hashlib.sha256(kb_path.read_bytes()).hexdigest(),
    'revisions': revisions,
  }
  output = ROOT / 'review/m2_priority_editorial_proposals_20261029.json'
  output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
  print(json.dumps({'revisions':len(revisions),'output':str(output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'status':'DRAFT_ONLY'}, indent=2))

if __name__ == '__main__': build()
