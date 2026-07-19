# GarageHUD Constitution v1.0

## Mission

GarageHUD exists to maximize the lifetime enjoyment, understanding, health, and value of every enthusiast's fleet through trusted data, thoughtful design, and intelligent insight.

## North Star

GarageHUD is the trusted digital steward of an enthusiast's vehicles throughout their entire lifecycle.

GarageHUD records.

Fleet Steward understands.

## What We Are Building

GarageHUD is not a garage app.

It is a **Vehicle Operating System**.

Its first application is GarageHUD.

Its intelligence is Fleet Steward.

## Fleet Steward

Fleet Steward is not a chatbot.

It is a reasoning engine.

It:

- Observes
- Remembers
- Understands
- Advises
- Predicts

It earns trust through evidence.

## Core Principles

### Trust

Never pretend certainty. Always explain recommendations. Show confidence. Protect user data.

The vehicle record owns truth. Fleet Steward may interpret that record; an assistant may explain
the interpretation. Neither may invent or directly mutate a part, date, price, measurement,
service event, or conclusion. Missing evidence is **undocumented**, **unknown**, or a question for
the owner — never proof that something is absent.

### Stewardship

Optimize for lifetime ownership. Not today's convenience.

### History over State

Everything important becomes part of the vehicle's biography. Nothing meaningful is forgotten.

### Observe First. Advise Second.

Steward watches long before it speaks. Recommendations must be earned.

### Every Warning Has A Door

An observation that asks the owner to act must lead directly to the evidence and a focused,
truth-preserving resolution. “Oil is overdue” must offer actions such as mark serviced, edit the
schedule, or review history. A warning that sends the owner hunting through a broad screen is not
finished.

### Calm Confidence

The interface should reduce uncertainty. Not create excitement.

### Information Has Gravity

Important things deserve attention. Everything else supports them.

### The Car Is The Hero

GarageHUD never competes with the vehicle. It exists to deepen the owner's relationship with it.

## Fleet Steward Language

Avoid:

> I think…

Prefer:

> I observed…
> The data suggests…
> Based on your history…
> Evidence: strong

Confidence is shown as an **evidence band** (`CONFIRMED / STRONG / MODERATE / WEAK /
INSUFFICIENT`), derived from evidence completeness — never a fabricated percentage. Earlier
drafts of this document used numeric confidence (e.g. "Confidence: 87%"); that was superseded
because a hand-authored percentage implies a statistical rigor the system does not have. See
[ADR-0003](adr/ADR-0003-evidence-bands.md).

## Development Philosophy

Build one horizon ahead. Don't architect for fantasies.

Every abstraction must make a likely feature within the next 12–18 months materially easier.

Delete complexity whenever possible.

## UX Philosophy

The user should almost subconsciously know where to look.

Motion explains. Never decorates.

Driving mode is voice-first. Typing while driving is considered a design failure.

## Voice

Voice is mandatory. Not because it's cool. Because it is safer and more natural.

The interaction model is:

> Steward…
> Go ahead.
> Start a log.
> Logging started.

Conversation. Not commands.

## Data Philosophy

Everything belongs somewhere.

Receipt → Repair → Event → Vehicle → Fleet → Owner → Story

The story is the product.

Three money facts remain separate: purchase price, build investment, and service spend. Unknown
prices remain unknown, never zero. Partial pricing must never replace a larger documented total.

A telemetry frame is not automatically measured. Each value independently carries its source,
timestamp, and quality; stale data becomes unavailable rather than continuing to look live.

## Long-Term Vision

GarageHUD should become the world's most trusted digital steward for enthusiast vehicles.

Not because of AI. Because of:

- Memory
- Judgment
- Context
- Trust
- Philosophy

AI is replaceable. Trust is not.

## Roles

**Tim**

- Vision
- Product
- Enthusiast mindset
- Final decisions

**Technical Director**

- Architecture
- Engineering
- Workflow
- Technical debt
- Long-term coherence

## Product Doctrine

GarageHUD records the story.

Fleet Steward helps the owner understand it.

Together they preserve, improve, and extend the lifetime experience of every enthusiast vehicle.
