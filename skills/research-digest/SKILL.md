---
name: research-digest
description: Weekly research paper digest — searches arXiv and the web for papers matching your interests, synthesizes key findings, and sends results via Telegram
license: MIT
compatibility: [macOS, Linux, Windows]
user-invocable: true
metadata:
  version: 0.1.0
  author: TheAiSingularity
  tags: [research, automation, telegram, cron, arxiv]
  requires_tools: [web_search, web_extract, memory, cron]
  required_environment_variables:
    - name: TELEGRAM_BOT_TOKEN
      prompt: "Your Telegram bot token (from @BotFather)"
      help_url: "https://core.telegram.org/bots/tutorial"
---

# research-digest

This skill generates a weekly digest of academic papers relevant to your research interests and delivers it via Telegram.

## When to invoke

- When the user asks for a research digest or paper summary
- When triggered by a cron schedule (e.g., "every Monday 8am")
- When the user wants to know what's new in their field

## Steps to execute

1. **Read research interests from memory**
   - Check MEMORY.md for the user's recorded research areas, current projects, and relevant keywords
   - If no interests are recorded, ask the user to describe their research focus before continuing

2. **Search for recent papers**
   - Use `web_search` to search arXiv for papers published in the last 7 days matching their interests
   - Search query pattern: `site:arxiv.org [research area] [current year-month]`
   - Run 2–3 searches with different keyword combinations to maximize coverage
   - Also search for papers via Google Scholar or Semantic Scholar if arXiv yields < 3 results

3. **Fetch and parse paper abstracts**
   - Use `web_extract` on each promising result to get the full abstract and metadata
   - Extract: title, authors, institution, date, abstract, link
   - Focus on papers that are directly relevant — filter out tangential results

4. **Select top 5 papers**
   - Rank by relevance to the user's stated interests
   - Prefer papers with strong empirical results or novel methodology
   - Include at least 1 paper that might be a "surprising finding" outside the user's usual scope

5. **Synthesize the digest**
   - For each paper: 2-sentence summary + 2–3 bullet points of key contributions
   - Write in plain language, avoiding unnecessary jargon
   - Note any papers that directly build on or contradict the user's current projects (check MEMORY.md)

6. **Deliver via Telegram**
   - Format for readability in Telegram (use bold headers, line breaks)
   - Send as: "Research Digest — Week of [date]" followed by numbered entries
   - Include arXiv links for each paper
   - End with: "Reply to discuss any of these papers or ask for a deeper dive"

7. **Update memory**
   - Save the digest summary (titles + key points only, not full text) to MEMORY.md under "Recent digests"
   - This enables future sessions to reference what was covered

## Output format

```
Research Digest — Week of [date]

1. [Paper Title] — [authors], [institution]
[2-sentence summary]
• [Key contribution 1]
• [Key contribution 2]
• [Key contribution 3]
arXiv: [link]

2. [Paper Title] ...
```

## Error handling

- If Telegram delivery fails: save digest to a file at `/sandbox/digest-[date].md` and notify via CLI
- If fewer than 3 relevant papers found: widen the search timeframe to 14 days and retry
- If arXiv is unreachable: try Semantic Scholar as fallback

## Notes

- The quality of this skill improves as the user records more research interests in memory
- After 5+ successful runs, Hermes will auto-optimize the search queries and summarization style for this user's preferences
