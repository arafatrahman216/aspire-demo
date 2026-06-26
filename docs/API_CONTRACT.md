# API Contract

## Base URL
`/api/v1`

---

## 1. Receive Lead Webhook

**Endpoint:** `POST /webhook`
**Summary:** Receives an inbound lead, validates the payload, performs AI analysis, and returns the qualification result.

### Request Body
`Content-Type: application/json`

| Field | Type | Required | Description |
|---|---|---|---|
| `full_name` | string | Yes | The full name of the lead |
| `email` | string | Yes | The contact email address |
| `message` | string | Yes | The lead's inquiry or message |
| `company_name` | string | No | The lead's company name |
| `job_title` | string | No | The lead's job title |
| `phone` | string | No | The lead's phone number |
| `company_size` | string | No | Size of the company |
| `budget_range` | string | No | Estimated budget range |

**Example Request:**
```json
{
  "full_name": "Jane Doe",
  "email": "jane@example.com",
  "company_name": "Acme Corp",
  "message": "We are looking to automate our lead qualification process."
}
```

### Successful Response (200 OK)
`Content-Type: application/json`

| Field | Type | Description |
|---|---|---|
| `status` | string | The processing status (e.g., "qualified", "low_context", "filtered", "qualified_fallback") |
| `lead_id` | string | The unique identifier generated for the lead |
| `lead_score` | integer | AI-generated score out of 100 |
| `priority_tier` | string | The priority tier (e.g., "High", "Medium", "Cold", "Manual Review") |
| `intent_summary` | string | AI-generated summary of the lead's intent |
| `suggested_opener` | string | AI-generated suggested email opener |
| `red_flags` | array of strings | Any detected red flags (or errors if fallback) |

**Example Response:**
```json
{
  "status": "qualified",
  "lead_id": "uuid-1234-5678",
  "lead_score": 85,
  "priority_tier": "High",
  "intent_summary": "Lead is highly interested in automation software.",
  "suggested_opener": "Hi Jane, I saw that Acme Corp is looking to automate lead qualification...",
  "red_flags": []
}
```

### Error Responses

#### 422 Unprocessable Entity
Returned when the request payload fails validation (e.g., missing required fields, invalid email format).

```json
{
  "error": "Validation Error",
  "details": [
    {
      "loc": ["body", "email"],
      "msg": "value is not a valid email address",
      "type": "value_error.email"
    }
  ]
}
```
