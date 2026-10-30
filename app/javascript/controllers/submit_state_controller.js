import { Controller } from "@hotwired/stimulus"

// Progressive enhancement for Turbo form submissions: no business writes,
// credentials, or tenant state are stored in the browser.
export default class extends Controller {
  start() {
    this.element.setAttribute("aria-busy", "true")
  }

  finish() {
    this.element.removeAttribute("aria-busy")
  }

  disconnect() {
    this.element.removeAttribute("aria-busy")
  }
}
