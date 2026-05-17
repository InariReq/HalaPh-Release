(function () {
  const navToggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-nav]");
  const toast = document.querySelector("[data-toast]");
  const year = document.querySelector("[data-year]");
  const themeButtons = document.querySelectorAll("[data-theme-option]");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const themeStorageKey = "halaph-showcase-theme";
  const allowedThemes = new Set(["light", "burgundy"]);

  function normalizeTheme(theme) {
    return allowedThemes.has(theme) ? theme : "light";
  }
  const validThemes = ["light", "dark", "burgundy", "navy"];

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
    const savedTheme = readSavedTheme();
    if (validThemes.includes(savedTheme)) return savedTheme;
    if (
      window.matchMedia &&
      window.matchMedia("(prefers-color-scheme: dark)").matches
    ) {
      return "dark";
    }
    return "light";
  }

  function applyTheme(theme, persist) {
    const nextTheme = validThemes.includes(theme) ? theme : "light";
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
  window.requestAnimationFrame(revealVisibleItems);
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
    summary: "Served as the overall head of TripLine PH. Guided the project direction, coordinated major decisions, monitored team progress, and helped keep the business proposal, HalaPH app, and presentation outputs aligned with the project objectives.",
    contributions: [
      "Led group coordination, project direction, task assignment, member progress checking, and final preparation support.",
      "Supported business proposal decisions, API-related coordination, major paperwork responsibilities, printing, and physical submission preparation.",
      "Helped with booth design planning, showcase booth preparation, Android build checking, and bug finding during app testing.",
      "Helped prepare, review, and improve the final paper."
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
    summary: "Managed day-to-day coordination, documentation flow, task follow-ups, and deadline tracking. Helped organize team responsibilities, supported communication between members, and contributed to advertisement video production and presentation preparation.",
    contributions: [
      "Led documentation work, organized written outputs, managed project files, and supported operations planning for the business proposal.",
      "Checked paper structure, formatting, completeness, consistency, and written materials for submission and presentation.",
      "Coordinated documentation needs with research and presentation requirements.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Led the technical side of HalaPH and handled the app development work using Flutter and Dart. Built and refined the mobile app, Firebase and Firestore integration, routing features, featured places system, advertisement tools, admin dashboard support, APK release flow, website deployment support, testing, debugging, and production-ready fixes.",
    contributions: [
      "Technical Development: Handled the development of the HalaPH mobile application using Flutter and Dart.",
      "App Features: Built and refined route guidance, trip planning, collaboration flows, favorites, profiles, guide mode, account tools, and polished user interfaces.",
      "Firebase and Backend Work: Worked on Firebase Authentication, Firestore data flows, Firestore rules, Firebase Storage, profile image syncing, friend systems, shared plans, account cleanup, and real-time data behavior.",
      "Routes and Places: Improved route-related features, fare support, Google Maps integration, cached destinations, featured places, admin-managed locations, and Explore screen behavior.",
      "Admin and Monetization Tools: Built and improved the admin dashboard, featured places management, advertisement controls, sponsored card behavior, delete controls, and dashboard statistics.",
      "Release and Deployment: Handled APK builds, public APK updates, QR/download support, showcase website updates, GitHub Pages deployment, and Firebase admin web deployment.",
      "Testing and Stability: Ran Dart analyze, Flutter analyze, Flutter tests, release builds, Xcode/iOS checks, Android checks, debugging, and production-ready fixes."
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
    summary: "Led the visual direction of HalaPH. Designed the app's look and feel, interface flow, branding direction, layout decisions, and user experience improvements. Directed the advertisement video and will lead its editing to keep the promotional output consistent with the HalaPH brand.",
    contributions: [
      "Led main design direction, UI/UX planning, visual layout support, color and presentation design discussions, and user-facing design improvements.",
      "Made the tarpaulin design for the showcase booth and made the brochure design and layout for the project presentation.",
      "Supported booth visuals, showcase design planning, Android build checking, and bug finding during app testing.",
      "Reviewed design-related paper and presentation sections, and helped prepare, review, and improve the final paper.",
      "Directed the advertisement video and will lead its editing."
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
    summary: "Conducts market research, competitor analysis, and user requirement gathering to support project planning and feature development. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Supported project research, information gathering, commuter and public transport review, and business proposal research sections.",
      "Reviewed research-based content and checked if written content matched project goals.",
      "Helped prepare proposal and presentation content through research support.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Collects, manages, and analyzes transport data such as routes, fare estimates, and destination information to support application accuracy. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Supported data analysis, route-related information review, commuter use case review, and app concept data support.",
      "Organized data used for proposal support and checked consistency of project information.",
      "Supported research and documentation with data-related input and proposal review.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Handles budgeting, capital management, financial projections, expense monitoring, and revenue planning from in-app advertisements. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Led finance planning, cost-related information preparation, budget planning, and business feasibility review.",
      "Supported pricing, funding, and ad-supported business model discussions for the proposal.",
      "Worked with the assistant finance role and reviewed finance-related paper sections.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Tracks expenses, monitors development costs, prepares financial reports, and helps develop budget-friendly features for HalaPH.",
    contributions: [
      "Assisted the Finance Manager with finance work, cost review, budget details, and business feasibility analysis.",
      "Helped organize financial information and check finance-related written content for clarity.",
      "Supported the business model section through finance-related input and review.",
      "Helped prepare, review, and improve the final paper."
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
    summary: "Creates marketing strategies and handles promotional activities for the project.",
    contributions: [
      "Led marketing planning, audience positioning, promotional ideas, and how HalaPH should be presented to students and commuters.",
      "Led booth design planning and helped align booth visuals with the HalaPH brand and app purpose.",
      "Supported brochure planning, presentation materials, and marketing-related paper review.",
      "Helped prepare, review, and improve the final paper."
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
    summary: "Plans and supervises advertising and promotional campaigns, including in-app advertisements, to reach target users. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Led advertisement planning, advertising direction, promotional content ideas, and ad-related showcase preparation.",
      "Coordinated advertisement-related tasks with advertisement officers and supported promotional material planning.",
      "Contributed to the ad-supported business concept and reviewed advertising-related paper and presentation details.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Creates promotional content, social media materials, advertising designs, and advertisement video support materials to increase awareness of HalaPH.",
    contributions: [
      "Assisted the Advertisement Manager with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Supported advertisement video or promotional material planning and ad-related presentation details.",
      "Reviewed advertising details for the paper and presentation.",
      "Helped prepare, review, and improve the final paper."
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
    summary: "Creates promotional content, social media materials, advertising designs, and advertisement video support materials to increase awareness of HalaPH. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Assisted the Advertisement Manager with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Supported advertisement video or promotional material planning and ad-related presentation details.",
      "Reviewed advertising details for the paper and presentation.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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
    summary: "Handles user feedback, concerns about routes, fares, and usability, and collects suggestions to improve the application. Also helped with and appeared in the advertisement video.",
    contributions: [
      "Supported customer support planning, user concern handling, and customer-facing service responsibilities.",
      "Helped review how users could ask for help, report concerns, and receive service support.",
      "Assisted with presentation support and customer support-related paper content.",
      "Helped prepare, review, and improve the final paper.",
      "Helped with and appeared in the advertisement video."
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

      requestAnimationFrame(() => {
        if (photo.complete && photo.naturalWidth > 0) {
          photo.classList.add("is-loaded");
          photo.classList.remove("is-missing");
        }
      });

      contributions.innerHTML = member.contributions
        .map((item) => `<li>${item}</li>`)
        .join("");

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
    value.textContent = active ? active.textContent.trim() : "Light";
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
