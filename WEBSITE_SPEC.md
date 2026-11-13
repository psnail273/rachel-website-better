# Rachel Siegel Website — Redesign Spec

Source: Rachel's "Website notes" Google Doc (PDF copy: `Website notes.pdf` in this repo), plus content carried over from the current site at https://rachel-website-smoky.vercel.app/.

Compiled 2026-11-13. Nothing has been built yet; this document is the full brief.

---

## 1. Overview

The redesign turns the site from a therapy-only practice site into a combined **psychotherapist + performing musician** site.

- **Name:** Rachel Siegel
- **Tagline:** Licensed psychotherapist, clarinetist, recorder player
- **Location:** St. Louis, MO

### Design references

| What | Reference | Notes |
|---|---|---|
| Homepage layout | https://www.lucidisano.com/ | "I'm stealing her layout, but **not her colors**." |
| "Upcoming" events scroll box | https://www.lucidisano.com/about-1 | Model the news-scroll look. |
| Education & Training page | https://www.eringrumley.com/education-and-training | A simple list, **not** boxes that look like links. |

### Color direction
No palette has been given; only "not Luci's colors." The chosen hero photo (pink/orange alpenglow, purple clouds, deep violet water) suggests a palette of dusky purples, soft pinks/corals and deep navy. This also suits both headshots (navy tops, purple tones). **To confirm with Rachel.**

---

## 2. Site map and navigation

Three tabs in the **top-right corner**, with dropdowns:

```
THERAPY ▾            PERFORMING ▾        CONTACT
  About Me             Bio                 → /contact page (see §6.5)
  Services             Media
  Education and Training
```

- **Contact** is its own page with two paths: one sends people to Wellness Alliance, the other emails Rachel directly (§6.5).
- The name/logo should link to the homepage.

### "Upcoming" footer visibility

| Page | Show "Upcoming" footer? |
|---|---|
| Home | ✅ Yes |
| Performing → Bio | ✅ Yes |
| Performing → Media | ✅ Yes |
| Therapy → About Me / Services / Education and Training | ❌ No |

---

## 3. Homepage

- Layout modelled on lucidisano.com (but different colors).
- Hero text:
  - **Rachel Siegel**
  - Licensed psychotherapist, clarinetist, recorder player
- **Background image:** the mountain lake photo (Rachel's choice; see §8, `hero-mountain-lake`).
  - Rachel's request: make it "a little more translucent or fuzzier so words can go on it without looking like a dumb PowerPoint." That means a soft blur and/or a tinted overlay or scrim behind the text so it's readable, while the photo stays clearly visible.
- **Footer: "Upcoming"** scroll box (see §4).

---

## 4. "Upcoming" events (footer component)

- Title: **Upcoming**
- A small **scrolling box** at the bottom of the page, modelled on Luci's news scroll (https://www.lucidisano.com/about-1).
- Rachel wants it to look "cute with the little boxes of events, rather than just one fat link." That means individual event cards, not a single "view calendar" link.
- Shown on Home + Performing pages only (see §2).

### Data source: public Google Calendar
- Share link: https://calendar.google.com/calendar/u/0/r?cid=ZjkzNTkzYTlhYThlZmRlZjliMjk2Y2QxM2FlNTUxOGMwODVhZDNlMWI2OWJiNjA5Mjc4ZTA5ZGYyZGM4OGVlNEBncm91cC5jYWxlbmRhci5nb29nbGUuY29t
- Decoded calendar ID: `f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4@group.calendar.google.com`
- Public iCal feed (likely the easiest way to get data for custom cards; check it once the calendar is confirmed public):
  `https://calendar.google.com/calendar/ical/f93593a9aa8efdef9b296cd13ae5518c085ad3e1b69bb609278e09df2dc88ee4%40group.calendar.google.com/public/basic.ics`
- Implementation options: (a) fetch and parse the public ICS server-side with revalidation (no API key); (b) Google Calendar API v3 with an API key; (c) a static fallback list. Only show future events.

### Events listed in the notes (fallback / seed data)

| Date(s) | Event |
|---|---|
| 6/23/26 | Opera Theater of St. Louis |
| 9/19/26 | Kingsbury Ensemble |
| 10/4/26 | Early Music Missouri |
| 10/16–18/26 | Philadelphia Orchestra — Harry Potter in Concert |
| 10/25/26 | Collegium Vocale |
| 11/6–8/26 | Nashville Symphony Orchestra — Harry Potter in Concert |
| 11/22/26 | American Kantorei |
| 2/26/27 | Con Spirito Concert Series — https://conspirito.kirkwoodpres.org/ |
| 3/1/27 | Chamber Music Society of St Louis |
| 5/14–16/27 | Early Music Missouri |

> As of 2026-11-13, the first six have already happened.

---

## 5. THERAPY section

### 5.1 About Me

**Formatting:** include a *small* copy of the therapist headshot (§8, `headshot-therapist`) somewhere in this section, next to or below some of the text, wherever looks good.

**Copy (verbatim from notes):**

> I believe every person holds the power to transform their life. It is my honor to be a part of that journey, helping empower my clients with the tools they need to build a more connected, joyful, and meaningful life.
>
> My background as a classical musician may, at first glance, appear to be unrelated to my work as a psychotherapist. But the insights I gained from this industry regarding self-inquiry, psychology, body awareness, and teamwork are highly applicable to therapeutic work and growth.
>
> Because of this background, I am especially passionate about working with high-achieving adolescents and adults, especially those struggling with maladaptive perfectionism. I also specialize in several related concerns, including:
>
> - Anxiety, chronic stress, and feeling constantly "on"
> - Self-doubt and imposter syndrome
> - Identity development
> - Depression and burnout
> - Work life balance/relationship issues
> - Eating and body image concerns
>
> In my sessions, I combine a warm, empathetic approach with evidence-based strategies. I draw especially upon ACT (Acceptance & Commitment Therapy) and CFT (Compassion Focused Therapy), both of which can help you develop flexibility in the face of adversity and build an authentic, values-driven life. I believe compassion, vulnerability, and having a safe space to just "be" are at the root of healing, and I look forward to providing that space for you.

**Pull quote:**

> *Let everything happen to you: beauty and terror. Just keep going. No feeling is final.*
> — Rainer Maria Rilke, *Letters to a Young Poet*

### 5.2 Services

**Copy (verbatim from notes):**

> I provide individual therapy to adults and adolescents (aged 14 and up) through a group practice, Wellness Alliance Counseling and Psychotherapy. In-person therapy takes place at our office in Clayton, MO. For telehealth, clients must be in Missouri or Illinois.

**Pull quote:**

> *And you may ask yourself, "Well, how did I get here?"* — Talking Heads

**You might be struggling with…**
- Identity development
- Anxiety and stress management
- Maladaptive perfectionism
- Self-doubt and imposter syndrome
- Depression or burnout
- Disordered eating and body image concerns
- Work-life balance
- Relationship issues/setting boundaries

**Therapy may help you…**
- Manage stress and anxiety
- Reframe unhelpful beliefs
- Develop greater self worth and self-confidence
- Cope with uncomfortable emotions and situations
- Increase compassion for yourself and others
- Develop self-care strategies
- Learn and set healthier boundaries in relationships and with work
- Move through creative or career blocks with clarity
- Explore identity outside of work/art/achievement
- Create work/performances that have meaning and purpose.

**A note on perfectionism…**

> Contrary to common belief, perfectionism usually doesn't help us achieve our goals. More often, it keeps us small, distracted by the fear of making a mistake or seeming messy. Perfectionism can cause:
>
> - Procrastination
> - Shame
> - Shutting down when emotional
> - Imposter syndrome
> - Obsession with achievement
> - Chronic stress and burnout
> - Frequent and intense anxiety of being perceived negatively.
>
> What if you could let that all go, and still be successful, loved and accepted as you are?

### 5.3 Education and Training

**Formatting:** like https://www.eringrumley.com/education-and-training. Just a simple list, **not** boxes that look like they should be links. The content is unchanged from the current site; only the formatting changes.

**Content (from the current site's About page):**

*Education & Credentials*
- MSW, Master of Social Work — Saint Louis University
- MM, Music Performance — University of Southern California
- BM, Music Performance — University of Minnesota – Twin Cities
- Clarinet Performance — Rice University *(degree type, e.g. graduate diploma or certificate, to confirm with Rachel)*

*Specialized Training*
- RO-DBT (Radically Open Dialectical Behavioral Therapy) Level 1
- Compassion Focused Therapy (Drs. Dennis Church and Paul Gilbert, Psychwire)
- Treating Adult ADHD (Margaret Dawson)
- Body Perfectionism: Innovative Tools from DBT, CBT, ACT ERP and More to Improve Self-Worth (Deanna Smith, PESI)
- Certification Training in DBT (Alexa Mulee, C-DBT)
- Understanding Adolescent Eating Disorders: Foundations in Family-Based Treatment (Washington University, St. Louis)
- Shamelessly Imperfect: A guide to Help Your Clients Break Free from Perfectionism (Milly Feliz, PESI)
- ACT 2-Day Intensive (Dr. DJ Moran)
- Mindfulness Certification Course, 2-Day Intensive (Dr. Debra Premashakti Alvis)
- Food and Mood: A Therapist's Guide to the Role of Nutrition in Mental Health (Kathleen Zamperini)

> The Rice University entry is new (it's not on the current site) and matches the performing bio.

---

## 6. PERFORMING section

### 6.1 Bio

**Formatting:** two columns, with the bio on one side and the **clarinet headshot** (§8, `headshot-clarinet`) on the other. Stacks on mobile.

**Copy (verbatim from notes):**

> As a performer of modern and historical wind instruments, Rachel Siegel defies conventional classifications. Across 34 states and for more than two decades, she has played music that spans a millennium, from orchestral works to ancient folk songs, on various eras of clarinets and recorders—all reflecting her eclectic musical interests and experiences.
>
> From 2013-2017, Rachel served as a clarinetist in "The President's Own" United States Marine Band in Washington, DC. In addition to her duties as a clarinetist and ceremonial musician, Rachel had the opportunity to perform Vivaldi's Recorder Concerto in C minor with "The President's Own" Chamber Orchestra. Since then, Rachel has performed (on clarinets of all sizes) with the St. Louis Symphony Orchestra, Washington National Opera Orchestra, Baltimore Symphony, and the Richmond Symphony. Additionally, since its debut in 2016, she has played recorder in the Harry Potter in Concert series with several orchestras, including the Philadelphia Orchestra and National Symphony Orchestra. Now based in her hometown of St. Louis, MO, Rachel is a regularly featured artist with Early Music Missouri and frequently collaborates with the Collegium Vocale of St. Louis and American Kantorei concert series.
>
> An advocate for the psychological wellbeing of performers and pedagogues within the field of classical music, Rachel teaches workshops to musicians of all ages on performance psychology and audition preparation. In all, thousands of students have worked with Rachel throughout the United States, including at universities such as Texas A&M, West Virginia University, and University of Missouri - St. Louis; at advanced youth programs like the St. Louis Symphony Youth Orchestra; and at dozens of schools across the country.
>
> Rachel received degrees in clarinet performance from the University of Minnesota, University of Southern California, and Rice University. Her primary teachers include Burt Hara, Yehuda Gilad and Tina Ward (clarinet), and Clea Galhano (recorder). Additionally, in 2020 she was awarded a Fulbright to study in Helsinki, Finland. In addition to performing, you can read about Rachel's work as a psychotherapist in the therapy section of this website.

- Suggest making "the therapy section of this website" a link to Therapy → About Me.
- Shows the "Upcoming" footer.

### 6.2 Media

**Formatting:** uploaded videos and audio, plus another headshot photo (the **recorder headshot**, §8, `headshot-recorder`). Shows the "Upcoming" footer.

**Video (YouTube embeds):**
- https://www.youtube.com/watch?v=VdwOjCyVsSE
- https://www.youtube.com/watch?v=DZA9Wi6KzWY

**Audio:**
- `20200121 2000 Rachel Siegel Brahms mvmt 4.wav` (**file needed**)
- `20200121 2000 Rachel Siegel Brahms mvmt 3.wav` (**file needed**)
  - Caption: *For access to the full Brahms Quintet performance, contact Rachel via email.* (**email address needed**)
- Radio broadcast of Chamber Music St. Louis concert, September 2025: *(audio clip to be uploaded soon)*. Show as "coming soon" or hide until available.

> Suggestion: convert the `.wav` files to `.mp3`/`.m4a` for the web; WAVs are very large.

---

## 6.5 Contact page

Route: `/contact`. The page offers two ways to get in touch:

1. **Therapy inquiries → Wellness Alliance:** direct people to https://wellnessalliancestl.com (Rachel sees therapy clients through this group practice).
2. **Email Rachel directly**, e.g. for performing, workshops or media requests: a `mailto:` link or button. **Email address to come.**

- Suggested copy: "For therapy, please reach out through Wellness Alliance" and "For performances, workshops or anything else, email me directly." (Wording to be confirmed with Rachel.)
- Whether the page shows the "Upcoming" footer isn't specified; default to **no**.

---

## 7. Removed / changed from the current site

| Current site | New plan |
|---|---|
| Home, About, Services, Rates, Contact (5 flat pages) | Home + Therapy ▾ (3) + Performing ▾ (2) + Contact page |
| Rates page ($125/50 min, free 20-min consult, sliding scale, insurance) | **Removed.** No rates or pricing anywhere on the new site. |
| Own contact form | Replaced by a Contact page: Wellness Alliance link (therapy) + direct email to Rachel |
| Footer with placeholder phone `(555) 123-4567` and `info@rachelsiegel.com` | Don't carry over the placeholder phone. Confirm the email. |
| Placeholder hero / headshot images | Real photos (see §8) |
| "Therapist & Coach" branding, coaching service | New tagline: "Licensed psychotherapist, clarinetist, recorder player." Coaching isn't mentioned in the notes. |

---

## 8. Image assets

All are embedded in `Website notes.pdf`. Rachel is sending **full-resolution originals**; use those when they arrive. (To pull the PDF versions out in the meantime: `pdfimages -png "Website notes.pdf" out/img`.)

| Key | Description | PDF size | Used on |
|---|---|---|---|
| `hero-mountain-lake` | Mountain lake at sunset, snow peaks lit pink/orange, purple clouds, reflections. **Chosen hero.** | 1920×1280 | Homepage background |
| `headshot-therapist` | Rachel in glasses, navy tee, purple-tinted hair, seated outdoors | 874×1184 | Therapy → About Me (small) |
| `headshot-clarinet` | Rachel holding a clarinet, floral navy dress, white blossoming trees | 768×1024 | Performing → Bio |
| `headshot-recorder` | Rachel holding a wooden recorder, pink cherry blossoms | 1471×2048 | Performing → Media |
| ~~`hero-lake-alt`~~ | Lake at sunset, green hills. **Not used: Adobe Stock watermark (#140709757), unlicensed.** | 1000×668 | — |

All images need meaningful alt text.

---

## 9. Open questions / pending from Rachel

- [ ] **Full-resolution photos** (in progress)
- [ ] Brahms `.wav` files (mvmt 3 & 4)
- [ ] **Rachel's direct email address** (needed on the Contact page, the Media page's "contact Rachel via email" line, and any footer contact info)
- [ ] Radio broadcast clip (Sept 2025): when available
- [ ] Contact page: link to the Wellness Alliance homepage (`https://wellnessalliancestl.com`) or a specific provider/contact page? Open in a new tab?
- [ ] Degree type for the Rice University entry in Education
- [ ] Confirm the Google Calendar is set to **public**, so the ICS feed works
- [ ] Color palette approval (the default direction is purples and pinks drawn from the hero photo)
- [ ] Footer content beyond "Upcoming" (copyright, email, social links?)
- [ ] Domain / deployment (the current site is on Vercel: `rachel-website-smoky.vercel.app`)

---

## 10. Technical notes

- Stack: Next.js 16 (App Router, `src/`), TypeScript, Tailwind CSS v4, pnpm; Node pinned via `.nvmrc` (v26.13.1).
- Suggested routes:
  - `/` (Home)
  - `/therapy/about`, `/therapy/services`, `/therapy/education-and-training`
  - `/performing/bio`, `/performing/media`
  - `/contact`
- Dropdown nav must work on touch and keyboard, with a mobile hamburger menu.
- The "Upcoming" component goes in a shared layout for Home + Performing routes only (e.g. a route group).
