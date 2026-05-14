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
      "Led group coordination and project direction.",
      "Helped assign tasks to members based on their project roles.",
      "Monitored group progress during paper preparation and presentation planning.",
      "Supported decision-making for the business proposal and showcase direction.",
      "Helped coordinate API-related project requirements.",
      "Handled major paperwork responsibilities during earlier project stages.",
      "Assisted with printing and physical submission preparation.",
      "Supported group revisions, checking, and final preparation.",
      "Helped with booth design planning and showcase booth preparation.",
      "Helped test the Android build and find bugs during app checking.",
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
      "Led full Flutter app development for HalaPH.",
      "Built and maintained major app screens including Home, Explore, Favorites, Friends, My Plans, Plan Details, Trip History, Settings, and Guide Mode.",
      "Implemented route planning, fare estimate support, destination browsing, search behavior, and commute-related app flows.",
      "Developed shared plan and collaboration features, including participant handling and friend-based planning flows.",
      "Integrated Firebase Auth, Cloud Firestore, Firebase Storage, and live app data updates.",
      "Implemented plan banners, image handling, profile-related fixes, friend system fixes, and account cleanup improvements.",
      "Built and refined plan reminders, trip history movement, finished trip behavior, and local notification handling.",
      "Added admin-to-user integration for App Settings, Featured Places, Admin Locations, Sponsored Cards, and Fullscreen Ads.",
      "Implemented live app settings refresh so Home and Explore update ads and settings without app restart.",
      "Handled sponsored card placement on Home and Explore with non-intrusive behavior.",
      "Added controlled fullscreen ad behavior after finishing a trip, with App Settings control and X-only close behavior.",
      "Removed banner ads as a user-facing ad format while keeping legacy-safe compatibility.",
      "Fixed admin role hierarchy so Owner, Head Admin, and Admin permissions match their authority level.",
      "Updated the Android APK download file for the showcase website.",
      "Regenerated QR codes for the site and APK download.",
      "Updated showcase website text, download section, FAQ wording, and release information.",
      "Ran technical validation using dart analyze, flutter analyze, flutter test, Android release build, and web release build.",
      "Created Git commits, tags, stable checkpoints, and release safeguards throughout development.",
      "Handled debugging through terminal logs, Xcode logs, Android build output, and Firebase permission issues.",
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
      "Led the main design direction for the HalaPH concept.",
      "Supported UI/UX planning for user-facing screens.",
      "Helped define the app's visual direction, layout, and presentation style.",
      "Provided design-related input for layout, visual hierarchy, and user experience.",
      "Supported logo, color, and presentation design discussions.",
      "Helped improve the visual quality of project materials.",
      "Assisted with booth and showcase visual planning when needed.",
      "Made the tarpaulin design for the showcase booth.",
      "Made the brochure design and layout for the project presentation.",
      "Helped test the Android build and find bugs during app checking.",
      "Reviewed design-related sections of the paper and presentation.",
      "Helped prepare, review, and improve the final paper."
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
      "Managed documentation-related responsibilities for the group.",
      "Helped organize written outputs and project files.",
      "Supported operations planning for the business proposal.",
      "Assisted with checking paper structure, formatting, and completeness.",
      "Helped prepare written materials for submission and presentation.",
      "Supported coordination between documentation, research, and presentation needs.",
      "Helped maintain consistency in project information across documents.",
      "Reviewed and improved documentation sections before finalization.",
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
      "Led finance-related planning for the business proposal.",
      "Helped prepare cost-related information for the project.",
      "Supported discussions on app pricing, funding, and business feasibility.",
      "Reviewed financial details used in the proposal.",
      "Helped align the business model with the app's free-download and ad-supported concept.",
      "Supported budget-related planning for presentation and showcase needs.",
      "Worked with the assistant finance role on finance-related paper details.",
      "Reviewed and improved finance-related sections of the paper.",
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
      "Assisted the Finance Manager with finance-related work.",
      "Helped review cost, budget, and business feasibility details.",
      "Supported finance analysis for the proposal.",
      "Helped check finance-related written content for clarity.",
      "Assisted with organizing financial information used in the paper.",
      "Supported the business model section through finance-related input.",
      "Reviewed finance details before final paper preparation.",
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
      "Led marketing-related planning for the project.",
      "Helped plan how HalaPH should be presented to students and commuters.",
      "Supported booth design direction for the showcase.",
      "Helped prepare visual and promotional ideas for the presentation.",
      "Contributed to marketing strategy and audience positioning.",
      "Supported brochure and presentation material planning.",
      "Helped align booth design with the HalaPH brand and app purpose.",
      "Reviewed marketing-related paper content.",
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
      "Led advertisement-related planning for the group.",
      "Helped prepare the advertising direction for HalaPH.",
      "Supported promotional content ideas for the project.",
      "Helped coordinate advertisement-related tasks with advertisement officers.",
      "Contributed to the ad-supported concept of the business proposal.",
      "Assisted with advertisement video and promotional material planning.",
      "Reviewed advertising-related sections and presentation details.",
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
      "Supported data analysis for the HalaPH concept.",
      "Helped review information related to routes, commuters, and app use cases.",
      "Assisted in organizing data used for proposal support.",
      "Helped check consistency of information in project materials.",
      "Supported research and documentation with data-related input.",
      "Reviewed data-related parts of the business proposal.",
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
      "Helped gather research for the project concept.",
      "Supported review of information related to commuters and public transport.",
      "Assisted with business proposal research sections.",
      "Helped check if written content matched the project goals.",
      "Supported documentation by reviewing research-based content.",
      "Helped prepare content for presentation and paper improvement.",
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
      "Helped define the customer support role for the business concept.",
      "Supported discussion of how users may ask for help or report concerns.",
      "Helped review user-facing service responsibilities.",
      "Assisted with presentation support related to customer handling.",
      "Supported the paper by reviewing customer support and service-related content.",
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
      "Assisted the Advertisement Manager with ad-related tasks.",
      "Helped prepare advertising and promotional ideas.",
      "Supported advertisement video or promotional material planning.",
      "Helped with showcase preparation related to advertising.",
      "Reviewed ad-related details for the paper and presentation.",
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
      "Assisted the Advertisement Manager with ad-related tasks.",
      "Helped prepare advertising and promotional ideas.",
      "Supported advertisement video or promotional material planning.",
      "Helped with showcase preparation related to advertising.",
      "Reviewed ad-related details for the paper and presentation.",
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
