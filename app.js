(function () {
  const navToggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-nav]");
  const toast = document.querySelector("[data-toast]");
  const year = document.querySelector("[data-year]");
  const themeButtons = document.querySelectorAll("[data-theme-option]");
  const themeStorageKey = "halaph-showcase-theme";
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

  if (navToggle && nav) {
    navToggle.addEventListener("click", () => {
      const isOpen = nav.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", String(isOpen));
      document.body.classList.toggle("nav-open", isOpen);
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        nav.classList.remove("open");
        navToggle.setAttribute("aria-expanded", "false");
        document.body.classList.remove("nav-open");
      });
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
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  document.querySelectorAll("[data-placeholder-link]").forEach((link) => {
    link.addEventListener("click", (event) => {
      const href = link.getAttribute("href") || "";
      const isPlaceholder =
        href.includes("_HERE") ||
        href === "ANDROID_APK_URL_HERE" ||
        href === "DEMO_VIDEO_URL_HERE" ||
        href === "WEBSITE_URL_HERE" ||
        href === "mailto:CONTACT_EMAIL_HERE";
      if (!isPlaceholder) return;
      event.preventDefault();
      showToast("Placeholder link. Replace it before the live showcase.");
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
        
      });
    },
    {
      threshold: 0.16,
      rootMargin: "0px 0px -40px 0px",
    },
  );

  revealItems.forEach((item) => revealObserver.observe(item));
})();


const teamMembers = [
  {
    name: "Carlos, John Jian S.",
    role: "General Manager",
    category: "Leadership",
    initials: "JC",
    photo: "assets/team/john-jian-carlos.jpg",
    image: "assets/team/john-jian-carlos.jpg",
    imageUrl: "assets/team/john-jian-carlos.jpg",
    summary: "Served as General Manager and overall group leader for TripLine PH.",
    contributions: [
      "Led group coordination, project direction, task assignment, member progress checking, and final preparation support.",
      "Supported business proposal decisions, API-related coordination, major paperwork responsibilities, printing, and physical submission preparation.",
      "Helped with booth design planning, showcase booth preparation, Android build checking, and bug finding during app testing.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Cheong, Jerald Jia Le D.",
    role: "Technical Lead / Senior App Developer",
    category: "Development",
    initials: "JC",
    photo: "assets/team/cheong-jia-le.jpg",
    image: "assets/team/cheong-jia-le.jpg",
    imageUrl: "assets/team/cheong-jia-le.jpg",
    summary: "Served as Technical Lead and Senior App Developer, leading the working HalaPH app, admin system integration, APK release, QR download flow, and showcase website updates.",
    contributions: [
      "Led full Flutter app development for HalaPH, including Home, Explore, Favorites, Friends, My Plans, Plan Details, Trip History, Settings, and Guide Mode.",
      "Built the main commute-planning features, including destination browsing, route planning, fare estimates, search behavior, shared plans, collaboration flows, reminders, and finished-trip history.",
      "Integrated and debugged Firebase features, including Auth, Cloud Firestore, Firebase Storage, live app data updates, profile handling, friend system fixes, plan banners, and account cleanup improvements.",
      "Built the admin-to-user system, including App Settings, Featured Places, Admin Locations, Sponsored Cards, Fullscreen Ads, live settings refresh, and role-based admin permissions.",
      "Handled ad system refinement, including non-intrusive sponsored cards, fullscreen ads after finished trips, X-only fullscreen ad closing, banner ad deprecation, and ad setting controls.",
      "Updated the showcase release assets, including the Android APK download, APK QR code, site QR code, showcase website copy, download section, FAQ, and release information.",
      "Ran technical validation, release builds, debugging, Git commits, stable tags, Xcode log checks, Android build checks, Firebase permission checks, and final showcase testing.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Toh, Ynna Marie S.",
    role: "Main Designer / UI/UX Designer",
    category: "Design",
    initials: "YT",
    photo: "assets/team/ynna-toh.jpg",
    image: "assets/team/ynna-toh.jpg",
    imageUrl: "assets/team/ynna-toh.jpg",
    summary: "Served as Main Designer and UI/UX Designer for the project.",
    contributions: [
      "Led main design direction, UI/UX planning, visual layout support, color and presentation design discussions, and user-facing design improvements.",
      "Made the tarpaulin design for the showcase booth and made the brochure design and layout for the project presentation.",
      "Supported booth visuals, showcase design planning, Android build checking, and bug finding during app testing.",
      "Reviewed design-related paper and presentation sections, and helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Valdueza, Fritzver Ezra D.",
    role: "Operations Manager / Documentation Lead",
    category: "Operations",
    initials: "FV",
    photo: "assets/team/fritzver-valdueza.jpg",
    image: "assets/team/fritzver-valdueza.jpg",
    imageUrl: "assets/team/fritzver-valdueza.jpg",
    summary: "Served as Operations Manager and Documentation Lead.",
    contributions: [
      "Led documentation work, organized written outputs, managed project files, and supported operations planning for the business proposal.",
      "Checked paper structure, formatting, completeness, consistency, and written materials for submission and presentation.",
      "Coordinated documentation needs with research and presentation requirements.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Amad, Ervin Francis S.",
    role: "Finance Manager",
    category: "Finance",
    initials: "EA",
    photo: "assets/team/ervin-amad.jpg",
    image: "assets/team/ervin-amad.jpg",
    imageUrl: "assets/team/ervin-amad.jpg",
    summary: "Served as Finance Manager for TripLine PH.",
    contributions: [
      "Led finance planning, cost-related information preparation, budget planning, and business feasibility review.",
      "Supported pricing, funding, and ad-supported business model discussions for the proposal.",
      "Worked with the assistant finance role and reviewed finance-related paper sections.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Encarnacion, Brianna Angela D.",
    role: "Finance Analyst / Assistant Finance Manager",
    category: "Finance",
    initials: "BE",
    photo: "assets/team/angela-encarnacion.jpg",
    image: "assets/team/angela-encarnacion.jpg",
    imageUrl: "assets/team/angela-encarnacion.jpg",
    summary: "Served as Finance Analyst and Assistant Finance Manager.",
    contributions: [
      "Assisted the Finance Manager with finance work, cost review, budget details, and business feasibility analysis.",
      "Helped organize financial information and check finance-related written content for clarity.",
      "Supported the business model section through finance-related input and review.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Salivio, Mariah Dacara D.",
    role: "Marketing Manager / Booth Design Lead",
    category: "Marketing",
    initials: "MS",
    photo: "assets/team/maraiah-salivio.jpg",
    image: "assets/team/maraiah-salivio.jpg",
    imageUrl: "assets/team/maraiah-salivio.jpg",
    summary: "Served as Marketing Manager and Booth Design Lead.",
    contributions: [
      "Led marketing planning, audience positioning, promotional ideas, and how HalaPH should be presented to students and commuters.",
      "Led booth design planning and helped align booth visuals with the HalaPH brand and app purpose.",
      "Supported brochure planning, presentation materials, and marketing-related paper review.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Catubig, Dhustine G.",
    role: "Advertisement Manager",
    category: "Advertising",
    initials: "DC",
    photo: "assets/team/dhustine-catubig.jpg",
    image: "assets/team/dhustine-catubig.jpg",
    imageUrl: "assets/team/dhustine-catubig.jpg",
    summary: "Served as Advertisement Manager.",
    contributions: [
      "Led advertisement planning, advertising direction, promotional content ideas, and ad-related showcase preparation.",
      "Coordinated advertisement-related tasks with advertisement officers and supported promotional material planning.",
      "Contributed to the ad-supported business concept and reviewed advertising-related paper and presentation details.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Dela Cruz, Jian B.",
    role: "Data Analyst",
    category: "Research",
    initials: "JD",
    photo: "assets/team/jian-dela-cruz.png",
    image: "assets/team/jian-dela-cruz.png",
    imageUrl: "assets/team/jian-dela-cruz.png",
    summary: "Served as Data Analyst.",
    contributions: [
      "Supported data analysis, route-related information review, commuter use case review, and app concept data support.",
      "Organized data used for proposal support and checked consistency of project information.",
      "Supported research and documentation with data-related input and proposal review.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Barroga, Ej M.",
    role: "Research Analyst",
    category: "Research",
    initials: "EB",
    photo: "assets/team/ej-barroga.jpg",
    image: "assets/team/ej-barroga.jpg",
    imageUrl: "assets/team/ej-barroga.jpg",
    summary: "Served as Research Analyst.",
    contributions: [
      "Supported project research, information gathering, commuter and public transport review, and business proposal research sections.",
      "Reviewed research-based content and checked if written content matched project goals.",
      "Helped prepare proposal and presentation content through research support.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Abilo, Mark Jansen A.",
    role: "Customer Support Representative",
    category: "Support",
    initials: "MA",
    photo: "assets/team/mark-jansen-abilo.jpg",
    image: "assets/team/mark-jansen-abilo.jpg",
    imageUrl: "assets/team/mark-jansen-abilo.jpg",
    summary: "Served as Customer Support Representative.",
    contributions: [
      "Supported customer support planning, user concern handling, and customer-facing service responsibilities.",
      "Helped review how users could ask for help, report concerns, and receive service support.",
      "Assisted with presentation support and customer support-related paper content.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Alimen, Mark Ian B.",
    role: "Advertisement Officers",
    category: "Advertising",
    initials: "MA",
    photo: "assets/team/mark-ian-alimen.jpg",
    image: "assets/team/mark-ian-alimen.jpg",
    imageUrl: "assets/team/mark-ian-alimen.jpg",
    summary: "Served as one of the Advertisement Officers.",
    contributions: [
      "Assisted the Advertisement Manager with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Supported advertisement video or promotional material planning and ad-related presentation details.",
      "Reviewed advertising details for the paper and presentation.",
      "Helped prepare, review, and improve the final paper."
    ]
  },
  {
    name: "Ewag, Allen P.",
    role: "Advertisement Officers",
    category: "Advertising",
    initials: "AE",
    photo: "assets/team/allen-ewag.jpg",
    image: "assets/team/allen-ewag.jpg",
    imageUrl: "assets/team/allen-ewag.jpg",
    summary: "Served as one of the Advertisement Officers.",
    contributions: [
      "Assisted the Advertisement Manager with advertisement tasks, promotional ideas, and showcase advertising preparation.",
      "Supported advertisement video or promotional material planning and ad-related presentation details.",
      "Reviewed advertising details for the paper and presentation.",
      "Helped prepare, review, and improve the final paper."
    ]
  }
];

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

  const render = (nextIndex) => {
    index = (nextIndex + teamMembers.length) % teamMembers.length;
    const member = teamMembers[index];

    card.classList.add("is-changing");

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
    }, 140);
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
