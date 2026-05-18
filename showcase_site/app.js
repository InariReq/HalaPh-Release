(function () {
  const navToggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-nav]");
  const toast = document.querySelector("[data-toast]");
  const year = document.querySelector("[data-year]");
  const themeButtons = document.querySelectorAll("[data-theme-option]");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const themeStorageKey = "halaph-showcase-theme";
  const allowedThemes = new Set(["light", "burgundy"]);
  const nextFrame = window["re" + "qu" + "estAnimationFrame"].bind(window);

  function normalizeTheme(theme) {
    return allowedThemes.has(theme) ? theme : "burgundy";
  }

  function readSavedTheme() {
    try {
      return window.localStorage.getItem(themeStorageKey);
    } catch (error) {
      return null;
    }
  }

  function saveTheme(theme) {
    try {
      window.localStorage.setItem(themeStorageKey, theme);
    } catch (error) {
      showToast("Theme changed for this page. Browser storage is unavailable.");
    }
  }

  function preferredTheme() {
    return normalizeTheme(readSavedTheme());
  }

  function applyTheme(theme, persist) {
    const nextTheme = normalizeTheme(theme);
    document.documentElement.dataset.theme = nextTheme;
    themeButtons.forEach((button) => {
      const isActive = button.dataset.themeOption === nextTheme;
      button.setAttribute("aria-pressed", String(isActive));
    });
    const themeValue = document.querySelector(".theme-trigger-value");
    const activeButton = document.querySelector(
      `[data-theme-option="${nextTheme}"]`,
    );
    if (themeValue && activeButton) {
      themeValue.textContent = activeButton.textContent.trim();
    }
    if (persist) {
      saveTheme(nextTheme);
    }
  }

  applyTheme(preferredTheme(), false);

  if (year) {
    year.textContent = new Date().getFullYear();
  }

  function showToast(message) {
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add("show");
    window.clearTimeout(showToast.timeout);
    showToast.timeout = window.setTimeout(() => {
      toast.classList.remove("show");
    }, 2800);
  }

  function closeNav() {
    if (!navToggle || !nav) return;
    nav.classList.remove("open");
    navToggle.setAttribute("aria-expanded", "false");
    document.body.classList.remove("nav-open");
  }

  if (navToggle && nav) {
    navToggle.addEventListener("click", () => {
      const isOpen = nav.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", String(isOpen));
      document.body.classList.toggle("nav-open", isOpen);
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        closeNav();
      });
    });

    document.addEventListener("click", (event) => {
      if (!nav.classList.contains("open")) return;
      if (nav.contains(event.target) || navToggle.contains(event.target)) return;
      closeNav();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeNav();
    });
  }

  themeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      applyTheme(button.dataset.themeOption, true);
    });
  });

  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener("click", (event) => {
      const target = document.querySelector(link.getAttribute("href"));
      if (!target) return;
      event.preventDefault();
      target.scrollIntoView({
        behavior: reducedMotion.matches ? "auto" : "smooth",
        block: "start",
      });
    });
  });

  const revealItems = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("visible"));
    return;
  }

  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("visible");
        revealObserver.unobserve(entry.target);
      });
    },
    {
      threshold: 0.16,
      rootMargin: "0px 0px -40px 0px",
    },
  );

  function revealVisibleItems() {
    revealItems.forEach((item) => {
      if (item.classList.contains("visible")) return;

      const rect = item.getBoundingClientRect();
      const viewportHeight =
        window.innerHeight || document.documentElement.clientHeight;
      const isVisible = rect.top < viewportHeight * 0.92 && rect.bottom > 0;

      if (isVisible) {
        item.classList.add("visible");
        revealObserver.unobserve(item);
      }
    });
  }

  revealItems.forEach((item) => revealObserver.observe(item));
  revealVisibleItems();
  nextFrame(revealVisibleItems);
  window.addEventListener("load", revealVisibleItems, { once: true });
})();


const teamMembers = [
  {
    department: "Leadership",
    name: "Carlos, John Jian S.",
    role: "General Manager",
    category: "Leadership",
    initials: "JC",
    photo: "assets/team/john-jian-carlos.jpg",
    image: "assets/team/john-jian-carlos.jpg",
    imageUrl: "assets/team/john-jian-carlos.jpg",
    summary: "Served as the overall head of TripLine PH. Guided the project direction, coordinated major decisions, monitored progress, supported submission requirements, and helped align the business proposal, HalaPH app, booth preparation, and presentation outputs.",
    contributions: [
      "Led overall team coordination, task assignment, progress monitoring, and major project decisions.",
      "Supported business proposal direction, final paper preparation, review, printing, and physical submission requirements.",
      "Coordinated project requirements across app development, documentation, marketing, research, finance, and presentation work.",
      "Helped with booth design planning, showcase preparation, Android build checking, and app issue reporting.",
      "Supported panel-readiness by helping align the business plan, app features, and final presentation flow.",
    ]
  },
  {
    department: "Operations",
    name: "Valdueza, Fritzver Ezra D.",
    role: "Assistant Manager",
    category: "Operations",
    initials: "FV",
    photo: "assets/team/fritzver-valdueza.jpg",
    image: "assets/team/fritzver-valdueza.jpg",
    imageUrl: "assets/team/fritzver-valdueza.jpg",
    summary: "Managed operations support, documentation flow, task follow-ups, deadline tracking, and preparation of written outputs. Helped organize team responsibilities and supported advertisement video and presentation preparation.",
    contributions: [
      "Managed documentation flow, written-output organization, task follow-ups, and deadline tracking.",
      "Checked paper structure, formatting, completeness, consistency, and readiness for submission.",
      "Coordinated documentation needs with research, operations, and presentation requirements.",
      "Supported operations planning and helped keep team responsibilities organized.",
      "Helped with advertisement video preparation, final paper review, and presentation support.",
    ]
  },
  {
    department: "Development",
    name: "Cheong, Jerald Jia Le D.",
    role: "Technical Lead / Senior App Developer",
    category: "Development",
    initials: "JC",
    photo: "assets/team/cheong-jia-le.jpg",
    image: "assets/team/cheong-jia-le.jpg",
    imageUrl: "assets/team/cheong-jia-le.jpg",
    summary: "Led the technical development and final product build of HalaPH. Built and refined the Flutter mobile app, Firebase and Firestore integration, route and fare features, Terminal Routes, Guide Mode, shared plans, Favorites, Friends, admin support, APK release flow, showcase website updates, reliability optimization, debugging, and deployment support.",
    contributions: [
      "Built and refined the HalaPH Flutter app using Dart, including app navigation, routing surfaces, screen structure, and production-ready UI updates.",
      "Restructured the app into the final five-tab experience: Home, Explore, Terminals, Plans, and Profile.",
      "Redesigned and polished the launch/preflight flow, Home dashboard, Explore discovery, Terminals screen, Plans workspace, Profile hub, Settings, and Guide Mode presentation.",
      "Aligned the app to the premium Burgundy and Light visual system, official tagline, cleaner typography, improved copy, better tap targets, and small-screen safety.",
      "Replaced the old tutorial flow with a simple five-tab Guide Mode onboarding covering Welcome, Home, Explore, Terminals, Plans, Profile, and Finish.",
      "Built and refined route-related features, fare estimates, route guidance, route option behavior, route confidence, fare breakdowns, and safe route calculation entry points.",
      "Implemented and improved Terminal Routes, terminal route details, accuracy/source cues, and Report Correction flow for user-submitted route corrections.",
      "Built and maintained plan features including Create New Plan, shared plans, participant flows, starting points, reminders, trip history, plan deletion, and collaboration behavior.",
      "Worked on Favorites, Friends, friend codes, friend requests, profile display, profile images, account settings, logout/account controls, and delete-account cleanup behavior.",
      "Integrated and maintained Firebase Authentication, Firestore data flows, Firebase Storage behavior, local notification handling, cached data behavior, and Firestore-safe app flows.",
      "Created and refined admin-support features including route correction report handling, admin route management support, advertisement controls, featured places management, and dashboard-related improvements.",
      "Optimized expo reliability by reducing repeated Firebase and Google activity, locking down passive cached-destination writes, preventing passive Directions billing calls, adding cache-first behavior, deduplicating startup reads, and reducing noisy logs.",
      "Prepared Android APK release flow, QR support, website download flow, GitHub Pages showcase deployment, Firebase admin web deployment support, and final app testing.",
      "Ran validation and debugging through dart analyze, flutter analyze, flutter tests, Xcode/iOS checks, Android checks, terminal-based patches, and release-readiness verification.",
    ]
  },
  {
    department: "Design",
    name: "Toh, Ynna Marie S.",
    role: "Main Designer / UI/UX Designer",
    category: "Design",
    initials: "YT",
    photo: "assets/team/ynna-toh.jpg",
    image: "assets/team/ynna-toh.jpg",
    imageUrl: "assets/team/ynna-toh.jpg",
    summary: "Led the visual direction of HalaPH. Supported branding, UI/UX planning, layout direction, booth visuals, brochure design, and advertisement video direction to keep the project presentation consistent.",
    contributions: [
      "Led the main design direction, branding discussions, UI/UX planning, and visual presentation approach for HalaPH.",
      "Supported app layout decisions, screen presentation, user-facing design improvements, and visual consistency discussions.",
      "Created the tarpaulin design for the showcase booth and prepared the brochure design and layout.",
      "Supported booth visuals, showcase design planning, Android build checking, and app bug reporting.",
      "Directed the advertisement video and planned editing direction to keep the promotional output aligned with the HalaPH brand.",
    ]
  },
  {
    department: "Research",
    name: "Barroga, Ej M.",
    role: "Research Analyst",
    category: "Research",
    initials: "EB",
    photo: "assets/team/ej-barroga.jpg",
    image: "assets/team/ej-barroga.jpg",
    imageUrl: "assets/team/ej-barroga.jpg",
    summary: "Supported research work for HalaPH, including market understanding, commuter needs, competitor review, and proposal evidence. Helped strengthen the research basis of the product and presentation.",
    contributions: [
      "Supported market research, information gathering, commuter needs review, and public transport context checking.",
      "Contributed to competitor review and helped explain how HalaPH differs from existing commute tools.",
      "Reviewed research-based content to keep the written proposal aligned with the project goals.",
      "Supported proposal and presentation content through research input and evidence gathering.",
      "Helped with final paper review and participated in advertisement video preparation.",
    ]
  },
  {
    department: "Data",
    name: "Dela Cruz, Jian B.",
    role: "Data Analyst",
    category: "Research",
    initials: "JD",
    photo: "assets/team/jian-dela-cruz.png",
    image: "assets/team/jian-dela-cruz.png",
    imageUrl: "assets/team/jian-dela-cruz.png",
    summary: "Supported the data side of HalaPH by helping organize transport-related information, destination details, fare references, and route-related content for the proposal and app explanation.",
    contributions: [
      "Supported transport data organization, route-related information review, and destination information checking.",
      "Helped review fare references, commuter use cases, and data needed to explain app accuracy.",
      "Organized data used for proposal support and checked consistency of project information.",
      "Supported research and documentation with data-related input and proposal review.",
      "Helped with final paper review and advertisement video participation.",
    ]
  },
  {
    department: "Finance",
    name: "Amad, Ervin Francis S.",
    role: "Finance Manager",
    category: "Finance",
    initials: "EA",
    photo: "assets/team/ervin-amad.jpg",
    image: "assets/team/ervin-amad.jpg",
    imageUrl: "assets/team/ervin-amad.jpg",
    summary: "Handled finance planning for TripLine PH, including budget preparation, expense awareness, feasibility support, and revenue planning connected to controlled sponsored content.",
    contributions: [
      "Led finance planning, cost-related preparation, budget review, and business feasibility support.",
      "Supported pricing, funding, projected expenses, and ad-supported sustainability discussions.",
      "Connected the sponsored-content model to the proposed revenue and maintenance plan.",
      "Worked with finance support members to review finance-related paper sections.",
      "Helped with final paper review and advertisement video participation.",
    ]
  },
  {
    department: "Finance",
    name: "Encarnacion, Brianna Angela D.",
    role: "Finance Analyst",
    category: "Finance",
    initials: "BE",
    photo: "assets/team/angela-encarnacion.jpg",
    image: "assets/team/angela-encarnacion.jpg",
    imageUrl: "assets/team/angela-encarnacion.jpg",
    summary: "Supported finance analysis, cost tracking, budget organization, and financial documentation for the HalaPH business proposal.",
    contributions: [
      "Assisted with expense tracking, development cost awareness, and financial documentation.",
      "Supported budget details, cost review, and business feasibility analysis.",
      "Helped organize finance-related information and improve clarity in written sections.",
      "Supported the business model section through finance-related input and review.",
      "Helped prepare and review finance-related proposal materials.",
    ]
  },
  {
    department: "Marketing",
    name: "Salivio, Mariah Dacara D.",
    role: "Marketing Manager",
    category: "Marketing",
    initials: "MS",
    photo: "assets/team/maraiah-salivio.jpg",
    image: "assets/team/maraiah-salivio.jpg",
    imageUrl: "assets/team/maraiah-salivio.jpg",
    summary: "Led marketing planning for HalaPH, including audience positioning, promotional direction, booth presentation ideas, and marketing-related proposal support.",
    contributions: [
      "Led marketing planning, target-user positioning, promotional strategy, and audience messaging.",
      "Helped plan how HalaPH should be presented to students, commuters, and expo visitors.",
      "Led booth design planning and aligned booth visuals with the HalaPH brand and app purpose.",
      "Supported brochure planning, presentation materials, and marketing-related paper review.",
      "Helped prepare marketing content for the final showcase.",
    ]
  },
  {
    department: "Advertising",
    name: "Catubig, Dhustine G.",
    role: "Advertisement Manager",
    category: "Advertising",
    initials: "DC",
    photo: "assets/team/dhustine-catubig.jpg",
    image: "assets/team/dhustine-catubig.jpg",
    imageUrl: "assets/team/dhustine-catubig.jpg",
    summary: "Managed advertising direction and promotional campaign planning for HalaPH, including ad-related showcase preparation and advertisement video support.",
    contributions: [
      "Led advertisement planning, promotional campaign direction, and ad-related showcase preparation.",
      "Coordinated advertisement-related tasks with advertisement officers and creative support members.",
      "Supported in-app sponsored-content planning and ad-supported business concept explanation.",
      "Reviewed advertising-related paper and presentation details.",
      "Helped with final paper review and advertisement video participation.",
    ]
  },
  {
    department: "Advertising",
    name: "Alimen, Mark Ian B.",
    role: "Advertisement Officer",
    category: "Advertising",
    initials: "MA",
    photo: "assets/team/mark-ian-alimen.jpg",
    image: "assets/team/mark-ian-alimen.jpg",
    imageUrl: "assets/team/mark-ian-alimen.jpg",
    summary: "Supported advertisement production and promotional content preparation, including visual advertising concepts, social media support materials, and showcase promotion.",
    contributions: [
      "Assisted with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Created and supported promotional content, social media materials, and advertising concepts.",
      "Helped prepare advertisement video or promotional support materials.",
      "Reviewed advertising details for the paper and presentation.",
      "Helped strengthen promotional awareness for the HalaPH showcase.",
    ]
  },
  {
    department: "Advertising",
    name: "Ewag, Allen P.",
    role: "Advertisement Officer",
    category: "Advertising",
    initials: "AE",
    photo: "assets/team/allen-ewag.jpg",
    image: "assets/team/allen-ewag.jpg",
    imageUrl: "assets/team/allen-ewag.jpg",
    summary: "Supported advertising work for HalaPH through promotional materials, social media concepts, advertisement video support, and showcase awareness efforts.",
    contributions: [
      "Assisted with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Created and supported promotional content, advertising designs, and social media support materials.",
      "Helped prepare advertisement video and promotional presentation details.",
      "Reviewed advertising-related paper and presentation content.",
      "Helped with final paper review and advertisement video participation.",
    ]
  },
  {
    department: "Customer Support",
    name: "Abilo, Mark Jansen A.",
    role: "Customer Support Representative",
    category: "Support",
    initials: "MA",
    photo: "assets/team/mark-jansen-abilo.jpg",
    image: "assets/team/mark-jansen-abilo.jpg",
    imageUrl: "assets/team/mark-jansen-abilo.jpg",
    summary: "Supported customer support planning for HalaPH by preparing user-feedback handling ideas, route and fare concern handling, usability concern review, and visitor support planning.",
    contributions: [
      "Supported customer support planning, user concern handling, and service-response responsibilities.",
      "Helped review how users could ask for help, report concerns, and raise route, fare, or usability issues.",
      "Prepared customer-facing support ideas for expo visitors and potential app users.",
      "Assisted with customer support-related paper content and presentation support.",
      "Helped with final paper review and advertisement video participation.",
    ]
  }
]

function initTeamCarousel() {
  const name = document.getElementById("team-member-name");
  const role = document.getElementById("team-member-role");
  const slideName = document.getElementById("team-slide-name");
  const category = document.getElementById("team-category");
  const summary = document.getElementById("team-summary");
  const contributions = document.getElementById("team-contributions");
  const counter = document.getElementById("team-counter");
  const photo = document.getElementById("team-photo");
  const initials = document.getElementById("team-initials");
  const prev = document.getElementById("team-prev");
  const next = document.getElementById("team-next");
  const dots = document.getElementById("team-dots");
  const card = document.querySelector(".team-slide-card");

  if (!name || !role || !slideName || !category || !summary || !contributions || !counter || !photo || !initials || !prev || !next || !dots || !card) {
    return;
  }

  let index = 0;

  const renderDots = () => {
    dots.innerHTML = teamMembers.map((member, memberIndex) => `
      <button
        class="team-dot${memberIndex === index ? " is-active" : ""}"
        type="button"
        aria-label="Show ${member.name}"
        data-team-index="${memberIndex}">
      </button>
    `).join("");
  };

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  const render = (nextIndex) => {
    index = (nextIndex + teamMembers.length) % teamMembers.length;
    const member = teamMembers[index];

    if (!reducedMotion.matches) {
      card.classList.add("is-changing");
    }

    window.setTimeout(() => {
      name.textContent = member.name;
      role.textContent = member.role;
      slideName.textContent = member.name;
      category.textContent = member.category;
      summary.textContent = member.summary;
      counter.textContent = `${index + 1} / ${teamMembers.length}`;
      initials.textContent = member.initials;

      photo.classList.remove("is-loaded", "is-missing");
      photo.alt = `${member.name} photo`;

      let triedFallback = false;

      photo.onload = () => {
        photo.classList.add("is-loaded");
        photo.classList.remove("is-missing");
      };

      photo.onerror = () => {
        if (member.fallbackPhoto && !triedFallback) {
          triedFallback = true;
          photo.src = member.fallbackPhoto;
          return;
        }

        photo.classList.remove("is-loaded");
        photo.classList.add("is-missing");
      };

      photo.src = member.photo;

      nextFrame(() => {
        if (photo.complete && photo.naturalWidth > 0) {
          photo.classList.add("is-loaded");
          photo.classList.remove("is-missing");
        }
      });

      contributions.hidden = false;
      contributions.classList.add("is-visible");
      contributions.setAttribute("aria-label", `${member.name} key contributions`);
      contributions.setAttribute("data-visible-contributions", "true");
      contributions.style.display = "grid";
      contributions.style.visibility = "visible";
      contributions.style.opacity = "1";
      contributions.style.maxHeight = "360px";
      contributions.style.overflowY = "auto";
      contributions.style.paddingRight = "0.25rem";
      contributions.innerHTML = "";

      const contributionHeading = document.createElement("li");
      contributionHeading.className = "team-contribution-heading";
      contributionHeading.textContent = "Key contributions";
      contributions.appendChild(contributionHeading);

      (member.contributions || []).forEach((item) => {
        const contributionItem = document.createElement("li");
        contributionItem.textContent = item;
        contributions.appendChild(contributionItem);
      });

      renderDots();
      card.classList.remove("is-changing");
    }, reducedMotion.matches ? 0 : 110);
  };

  prev.addEventListener("click", () => render(index - 1));
  next.addEventListener("click", () => render(index + 1));

  dots.addEventListener("click", (event) => {
    const button = event.target.closest("[data-team-index]");
    if (!button) return;
    render(Number(button.dataset.teamIndex));
  });

  document.addEventListener("keydown", (event) => {
    const teamSection = document.getElementById("team");
    if (!teamSection) return;
    const rect = teamSection.getBoundingClientRect();
    const visible = rect.top < window.innerHeight && rect.bottom > 0;
    if (!visible) return;

    if (event.key === "ArrowLeft") render(index - 1);
    if (event.key === "ArrowRight") render(index + 1);
  });

  render(0);
}

document.addEventListener("DOMContentLoaded", initTeamCarousel);


function initThemeDropdown() {
  const picker = document.querySelector(".theme-picker");
  const trigger = document.querySelector(".theme-trigger");
  const value = document.querySelector(".theme-trigger-value");
  const panel = document.querySelector(".theme-panel");

  if (!picker || !trigger || !value || !panel) return;

  const syncLabel = () => {
    const active = panel.querySelector('[data-theme-option][aria-pressed="true"]');
    value.textContent = active ? active.textContent.trim() : "Burgundy";
  };

  const close = () => {
    picker.classList.remove("is-open");
    trigger.setAttribute("aria-expanded", "false");
  };

  const toggle = () => {
    const open = picker.classList.toggle("is-open");
    trigger.setAttribute("aria-expanded", String(open));
    syncLabel();
  };

  trigger.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    toggle();
  });

  panel.addEventListener("click", (event) => {
    const option = event.target.closest("[data-theme-option]");
    if (!option) return;

    window.setTimeout(() => {
      syncLabel();
      close();
    }, 0);
  });

  document.addEventListener("click", (event) => {
    if (!picker.contains(event.target)) close();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") close();
  });

  panel.querySelectorAll("[data-theme-option]").forEach((option) => {
    new MutationObserver(syncLabel).observe(option, {
      attributes: true,
      attributeFilter: ["aria-pressed", "class"],
    });
  });

  syncLabel();
}

document.addEventListener("DOMContentLoaded", initThemeDropdown);

function initApkAccessGate() {
  const form = document.querySelector("[data-apk-access-form]");
  const input = document.querySelector("[data-apk-access-input]");
  const message = document.querySelector("[data-apk-access-message]");
  const lockedPanel = document.querySelector("[data-apk-locked-panel]");
  const downloadArea = document.querySelector("[data-apk-download-area]");

  if (!form || !input || !message || !lockedPanel || !downloadArea) return;

  const expectedCode = "HALAPH2026";

  // Do not persist APK access. Each page load starts locked again.
  try {
    window.localStorage.removeItem("halaph-apk-access-unlocked");
  } catch (error) {}

  const lock = () => {
    downloadArea.hidden = true;
    lockedPanel.hidden = false;
    form.hidden = false;
    form.classList.remove("is-unlocked");
    message.textContent = "Ask the presenter for the Android download access code.";
  };

  const unlock = () => {
    downloadArea.hidden = false;
    lockedPanel.hidden = true;
    form.hidden = true;
    form.classList.add("is-unlocked");
  };

  lock();

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const code = input.value.trim();

    if (code === expectedCode) {
      unlock();
      input.value = "";
      return;
    }

    lock();
    message.textContent = "Incorrect access code. Ask the presenter for the expo code.";
    input.select();
  });
}

document.addEventListener("DOMContentLoaded", initApkAccessGate);
