(function () {
  var STORAGE_KEY = "anypip-lang";
  var buttons = document.querySelectorAll("[data-set-lang]");

  function applyLang(lang) {
    document.documentElement.setAttribute("lang", lang);
    buttons.forEach(function (btn) {
      btn.classList.toggle("active", btn.dataset.setLang === lang);
    });
    try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) {}
  }

  function initialLang() {
    var stored = null;
    try { stored = localStorage.getItem(STORAGE_KEY); } catch (e) {}
    if (stored === "fr" || stored === "en") return stored;
    return navigator.language && navigator.language.toLowerCase().indexOf("fr") === 0 ? "fr" : "en";
  }

  buttons.forEach(function (btn) {
    btn.addEventListener("click", function () { applyLang(btn.dataset.setLang); });
  });

  applyLang(initialLang());

  var yearEl = document.getElementById("copyright-year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // Mobile nav toggle
  var navToggle = document.getElementById("nav-toggle");
  var siteNav = document.getElementById("site-nav");
  if (navToggle && siteNav) {
    navToggle.addEventListener("click", function () {
      var open = siteNav.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    siteNav.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        siteNav.classList.remove("open");
        navToggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  // Contact form
  var STATUS_TEXT = {
    ok: { fr: "Message envoyé, merci ! Je réponds au plus vite.", en: "Message sent, thank you! I'll reply as soon as I can." },
    invalid_name: { fr: "Merci d'indiquer votre nom.", en: "Please enter your name." },
    invalid_email: { fr: "Cette adresse email n'est pas valide.", en: "That email address isn't valid." },
    invalid_message: { fr: "Le message est vide ou trop long.", en: "The message is empty or too long." },
    send_failed: { fr: "L'envoi a échoué. Réessayez plus tard ou écrivez à david@markowicz.fr.", en: "Sending failed. Try again later or write to david@markowicz.fr." },
    method_not_allowed: { fr: "Une erreur est survenue.", en: "Something went wrong." },
    network_error: { fr: "Impossible de contacter le serveur. Vérifiez votre connexion.", en: "Couldn't reach the server. Check your connection." }
  };

  function currentLang() {
    return document.documentElement.getAttribute("lang") === "en" ? "en" : "fr";
  }

  function showStatus(el, code, success) {
    var text = (STATUS_TEXT[code] || STATUS_TEXT.network_error)[currentLang()];
    el.textContent = text;
    el.hidden = false;
    el.classList.toggle("form-status-success", success);
    el.classList.toggle("form-status-error", !success);
  }

  var form = document.getElementById("contact-form");
  var statusEl = document.getElementById("contact-status");
  var submitBtn = document.getElementById("contact-submit");

  if (form && statusEl) {
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (submitBtn) submitBtn.disabled = true;

      fetch(form.action, {
        method: "POST",
        headers: { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json" },
        body: new FormData(form)
      })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          showStatus(statusEl, data.code, !!data.success);
          if (data.success) form.reset();
        })
        .catch(function () {
          showStatus(statusEl, "network_error", false);
        })
        .finally(function () {
          if (submitBtn) submitBtn.disabled = false;
        });
    });
  }

  // Fallback status after a non-JS submit redirect (?sent=1|0&code=...)
  if (statusEl) {
    var params = new URLSearchParams(window.location.search);
    if (params.has("sent")) {
      showStatus(statusEl, params.get("code") || "network_error", params.get("sent") === "1");
      var url = window.location.pathname + window.location.hash;
      window.history.replaceState({}, document.title, url);
    }
  }
})();
