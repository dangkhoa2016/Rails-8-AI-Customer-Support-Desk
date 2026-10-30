import { Controller } from "@hotwired/stimulus"

// No local state or credentials; only tenant/member-scoped GET requests.
export default class extends Controller {
  connect() { this.schedule() }
  loaded() { this.schedule() }
  schedule() {
    if (this.timeout) clearTimeout(this.timeout)
    if (this.element.querySelector('[data-ai-terminal="true"]')) return
    this.timeout = setTimeout(() => {
      if (this.element.isConnected && this.element.hasAttribute("src")) this.element.reload()
    }, 3000)
  }
  disconnect() { if (this.timeout) clearTimeout(this.timeout) }
}
