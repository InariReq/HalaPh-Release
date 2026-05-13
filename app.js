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
    photo: "assets/team/john-jian-carlos.jpg",
    initials: "JC",
    summary: "Served as the group leader, coordinated members, activated APIs, helped with paper documentation, handled major paperwork and printing, and served as one of the heads for advertisement video production.",
    contributions: [
      "Served as the group leader and general manager.",
      "Managed and coordinated group members.",
      "Activated the required APIs for the project.",
      "Joined brainstorming for the app concept and project plan with Jia Le, Fritzver, and Ynna.",
      "Helped with the project paper and documentation.",
      "Handled major paperwork responsibilities.",
      "Managed printing and preparation of physical paper outputs.",
      "Supported organization of printed materials for submission and presentation.",
      "Served as one of the heads for advertisement video production."
    ]
  },
  {
    name: "Cheong, C Jerald Jia Le D.",
    role: "Technical Lead / App Developer",
    category: "Core Development",
    photo: "assets/team/cheong-jia-le.jpg",
    initials: "CJ",
    summary: "Led the final app and website development, rebuilt the working HalaPH app, handled testing, debugging, UI polish, Firebase integration, and final showcase preparation.",
    contributions: [
      "Led the final technical development of HalaPH.",
      "Built the final working Flutter application.",
      "Rebuilt the app from the original prototype direction into the current showcase-ready version.",
      "Redesigned the final app UI, navigation flow, and user experience.",
      "Implemented route planning, route guide steps, fare estimates, fare breakdown UI, route confidence UI, and transport mode indicators.",
      "Built favorites, plans, trip history, shared plans, collaboration features, reminders, and Guide Mode.",
      "Integrated Firebase authentication, Firestore, Firebase Storage, and app data flows.",
      "Built the standalone HalaPH showcase website.",
      "Served as the primary app tester.",
      "Tested, debugged, validated, and refined the app for the live showcase.",
      "Handled bug fixes, UI polish, animation polish, runtime fixes, and final app stabilization.",
      "Helped with the project paper and documentation.",
      "Joined brainstorming for the app concept and project plan with Carlos, Fritzver, and Ynna.",
      "Prepared the final app demo and website for presentation use."
    ]
  },
  {
    name: "Toh, Ynna Marie S.",
    role: "UI/UX Designer",
    category: "Design Support",
    photo: "assets/team/ynna-toh.jpg",
    initials: "YT",
    summary: "Provided the base UI concept, created the app and business logos, worked on the brochure, helped with paper documentation, led booth design with Maraiah, and served as one of the heads for advertisement video production.",
    contributions: [
      "Provided the base UI concept for the application.",
      "Helped shape the early visual direction of HalaPH.",
      "Joined brainstorming for the app concept and project plan with Carlos, Jia Le, and Fritzver.",
      "Created the HalaPH app logo.",
      "Created the business logo.",
      "Worked on the project brochure.",
      "Helped with the project paper and documentation.",
      "Led booth design and preparation with Maraiah.",
      "Served as one of the heads for advertisement video production."
    ]
  },
  {
    name: "Valdueza, Fritzver Ezra D.",
    role: "Paper Auditor",
    category: "Documentation",
    photo: "assets/team/fritzver-valdueza.jpg",
    initials: "FV",
    summary: "Reviewed and corrected the project paper, joined brainstorming, supported booth design, and served as one of the heads for advertisement video production.",
    contributions: [
      "Reviewed and checked the project paper.",
      "Corrected paper content, formatting, and consistency.",
      "Helped improve the written documentation.",
      "Joined brainstorming for the app concept and project plan with Carlos, Jia Le, and Ynna.",
      "Supported booth design and preparation.",
      "Served as one of the heads for advertisement video production."
    ]
  },
  {
    name: "Salivio, Maraiah Decara D.",
    role: "Marketing Manager",
    category: "Marketing",
    photo: "assets/team/maraiah-salivio.jpg",
    initials: "MS",
    summary: "Led the marketing strategy, planned promotion, and led booth design and preparation with Ynna.",
    contributions: [
      "Led marketing strategy for HalaPH.",
      "Planned how the app would be promoted to users.",
      "Led booth design and preparation.",
      "Supported audience-facing presentation ideas.",
      "Helped shape the project’s promotional direction."
    ]
  },
  {
    name: "Amad, Ervin Francis S.",
    role: "Finance Manager",
    category: "Finance",
    photo: "assets/team/ervin-amad.jpg",
    initials: "EA",
    summary: "Handled finance-related proposal work, costing details, and budget organization.",
    contributions: [
      "Managed finance-related proposal parts.",
      "Prepared costing details for the project.",
      "Organized budget information.",
      "Supported the financial planning section of the business proposal."
    ]
  },
  {
    name: "Dela Cruz, Jian B.",
    role: "Data Analyst",
    category: "Research and Data",
    photo: "assets/team/jian-dela-cruz.jpg",
    fallbackPhoto: "assets/team/jian-dela-cruz.png",
    initials: "JD",
    summary: "Analyzed project data, reviewed proposal information, and supported booth design.",
    contributions: [
      "Analyzed project-related data.",
      "Reviewed information used for the proposal.",
      "Supported data organization and interpretation.",
      "Supported booth design and preparation."
    ]
  },
  {
    name: "Barroga, Ej M.",
    role: "Researcher",
    category: "Research",
    photo: "assets/team/ej-barroga.jpg",
    initials: "EB",
    summary: "Conducted market research, gathered supporting information, and supported project concept development.",
    contributions: [
      "Conducted market research for the project.",
      "Gathered supporting information for the proposal.",
      "Supported research references and project concept development.",
      "Supported booth design and preparation."
    ]
  },
  {
    name: "Catubig, Dhustine G.",
    role: "Advertisement Manager",
    category: "Advertising",
    photo: "assets/team/dhustine-catubig.jpg",
    initials: "DC",
    summary: "Managed advertisement tasks, promotion support, booth preparation, and participated in the advertisement video.",
    contributions: [
      "Managed advertisement-related tasks.",
      "Helped promote the HalaPH application.",
      "Supported promotional planning and campaign direction.",
      "Supported booth design and preparation.",
      "Participated in the advertisement video."
    ]
  },
  {
    name: "Encarnacion, Angela Brianna D.",
    role: "Assistant Auditor",
    category: "Documentation",
    photo: "assets/team/angela-encarnacion.jpg",
    initials: "AE",
    summary: "Assisted in paper auditing, documentation review, and booth preparation.",
    contributions: [
      "Assisted in auditing the project paper.",
      "Checked documentation accuracy and consistency.",
      "Supported paper review and final output preparation.",
      "Supported booth design and preparation."
    ]
  },
  {
    name: "Alimen, Mark Ian B.",
    role: "Advertisement Officer",
    category: "Advertising",
    photo: "assets/team/mark-ian-alimen.jpg",
    initials: "MA",
    summary: "Supported advertisement tasks, promotional materials, and booth preparation.",
    contributions: [
      "Supported advertisement tasks for the project.",
      "Helped promote the HalaPH application.",
      "Assisted with promotional materials and preparation.",
      "Supported booth design and preparation."
    ]
  },
  {
    name: "Ewag, Allen P.",
    role: "Advertisement Officer",
    category: "Advertising",
    photo: "assets/team/allen-ewag.jpg",
    initials: "AE",
    summary: "Supported advertisement tasks, promotional materials, and booth preparation.",
    contributions: [
      "Supported advertisement tasks for the project.",
      "Helped promote the HalaPH application.",
      "Assisted with promotional materials and preparation.",
      "Supported booth design and preparation."
    ]
  },
  {
    name: "Abilo, Mark Jansen A.",
    role: "Advertisement Officer",
    category: "Advertising",
    photo: "assets/team/mark-jansen-abilo.jpg",
    initials: "MA",
    summary: "Supported advertisement tasks, promotional materials, and booth preparation.",
    contributions: [
      "Supported advertisement tasks for the project.",
      "Helped promote the HalaPH application.",
      "Assisted with promotional materials and preparation.",
      "Supported booth design and preparation."
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
