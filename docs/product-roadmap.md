# DanceSage Product Roadmap

## Product vision

DanceSage helps people capture, understand, practise, and improve dance through video and pose-based movement feedback.

The product begins as a simple way to record dancers and create visually distinctive, shareable dance videos. It then grows into a teacher-and-student learning platform, an AI dance teacher grounded in a curated dance library, and finally an AI-assisted choreography system.

The first four phases belong to one focused progression:

1. Capture and review movement.
2. Learn from a human teacher.
3. Learn from DanceSage as an AI teacher.
4. Create combinations and routines with AI.

Music production is not part of this roadmap. DanceSage may use music selected or imported by the user, subject to platform and copyright requirements.

## Product principles

- Dance comes first. Technology should make movement easier to see and understand.
- Start simple and earn complexity through real user needs.
- Keep recordings private and on-device until sharing or cloud synchronization is deliberately introduced.
- Give dancers a small number of useful corrections instead of overwhelming them.
- Preserve teacher control when AI assists with instruction or evaluation.
- Build AI features from labelled, validated dance knowledge rather than unsupported generation.
- Make sharing enjoyable without turning the first product into a social network.

---

## Phase 1 — Capture, review, save, and share

### Goal

Deliver a reliable on-device application that records dancers, detects their poses, saves the results, and lets them review or share an attractive dance video.

### Core experiences

#### Styling mode

- Record one dancer using the front or rear camera.
- Detect and display the dancer's skeleton while recording.
- Keep the skeleton synchronized with the recorded video.

#### Partner mode

- Record two dancers.
- Detect and display a separate skeleton for each dancer.
- Maintain dancer identity as consistently as possible when dancers move or overlap.

#### Import mode

- Select an existing video from the phone.
- Play the video while pose extraction runs.
- Process frames without freezing the video interface.
- Save the processed video and skeleton timeline.

#### Playback

- View Video only.
- View Skeleton only on a clear background.
- View Video and Skeleton together.
- Play, pause, restart, and review the synchronized result.

#### Local library

- Name and save a recording on the phone.
- Retrieve saved recordings reliably after closing and reopening the app.
- Delete recordings intentionally.
- Keep the app functional without an account, backend, or internet connection.

### Social video export

DanceSage should help users create a finished video they can share through TikTok, Instagram, Messages, or any application supported by the iOS share sheet.

Export choices should include:

- Original video without the skeleton.
- Video with the DanceSage skeleton rendered into it.
- Skeleton-only animation on a selected background.
- A vertical 9:16 export suitable for TikTok and short-form video.
- Optional DanceSage branding that is tasteful and does not obscure the dancer.

The exported video must contain the chosen visual result permanently. Interactive controls such as switching the skeleton on and off remain inside DanceSage and cannot be transferred into a normal TikTok video.

Direct integration with the TikTok API is not required for Phase 1. A standard iOS share sheet provides a simpler and more flexible first implementation.

### Data foundation

Each recording should retain enough information to support future coaching features:

- Video file reference.
- Pose landmarks for every processed frame.
- Frame timestamps and recording duration.
- Landmark confidence or visibility when available.
- Styling or partner mode.
- Front or rear camera position.
- Orientation and mirroring information.
- Beat timestamps and estimated BPM when available.
- Pose-model name and version.

### Phase 1 completion criteria

- Recording works reliably with both cameras in portrait orientation.
- Styling and partner recordings can be saved and retrieved.
- Imported videos continue playing while pose extraction progresses.
- Video, Skeleton, and Both modes remain synchronized.
- Saved recordings survive an app restart.
- A finished vertical video can be exported and opened through the iOS share sheet.
- The core workflow works entirely on the phone.

---

## Phase 2 — Human teachers and students

### Goal

Turn DanceSage into a learning platform where teachers publish lessons, students practise them, and both receive a clear record of progress.

Phase 2 introduces accounts, roles, controlled sharing, and backend synchronization. These services should not be added to Phase 1 before the local recording experience is reliable.

### Roles

#### Teacher

- Create a teacher profile.
- Create and organize lessons by dance, level, topic, or move.
- Record or upload a reference demonstration.
- Add lesson notes, counts, music information, and teaching cues.
- Assign or share lessons with selected students.
- Review student attempts.
- Approve an attempt or return it with feedback.
- Track a student's progress across lessons.

#### Student

- Create a student profile.
- Connect with a teacher.
- Browse assigned or available lessons.
- Watch the teacher's Video, Skeleton, or Both view.
- Practise and record an attempt.
- Receive a small number of immediate movement cues.
- Submit an attempt to the teacher.
- Read teacher feedback and record another attempt.
- See lesson status and learning progress.

### Recommended delivery sequence

#### Phase 2A — Teacher/student lesson loop

Build the human workflow before automated scoring:

1. Teacher publishes a lesson.
2. Student watches and records an attempt.
3. Student submits the attempt.
4. Teacher reviews Video, Skeleton, or Both.
5. Teacher approves the attempt or provides feedback.
6. Student receives the result and may try again.

This stage validates whether teachers and students find the product useful without depending on AI quality.

#### Phase 2B — Movement comparison and assisted feedback

Compare the student's attempt with the teacher's reference using:

- Body-relative coordinates rather than raw screen position.
- Joint angles normalized for different body proportions.
- Movement sequence and direction.
- Beat, count, and transition timing.
- Left/right orientation and camera mirroring.
- Temporal alignment when teacher and student move at different speeds.
- Pose confidence so uncertain joints do not create confident corrections.

Feedback should focus on one or two actionable cues at a time. Examples include:

- "Raise your left elbow slightly."
- "Begin the turn one count later."
- "Keep your weight over the supporting foot."
- "Your timing is good; extend the arm line."

AI-generated suggestions should be visible to the teacher, who can approve, edit, or replace them.

### Phase 2 completion criteria

- Teacher and student accounts have clear permissions.
- Teachers can publish and assign lessons.
- Students can record and submit attempts.
- Teachers can review, comment on, and approve attempts.
- Notifications and lesson status are reliable.
- Automated feedback is understandable, limited, and tied to visible movement evidence.
- Private lesson and student data is protected in transit and at rest.

---

## Phase 3 — DanceSage as the AI teacher

### Goal

Allow a student to learn without a human teacher being present by grounding instruction and feedback in a curated, labelled dance knowledge base.

### Dance knowledge library

The library should represent more than a collection of videos. Each entry should include structured knowledge such as:

- Dance style and sub-style.
- Move or technique name.
- Leader, follower, solo styling, or partner role.
- Skill level and prerequisites.
- Counts, rhythm, BPM range, and musical context.
- Reference videos and pose sequences.
- Important joint relationships and movement phases.
- Valid variations.
- Common mistakes.
- Corrective cues and exercises.
- Safe transitions into and out of the movement.
- Labels reviewed by qualified dancers or teachers.

Salsa can be the first deep specialization. Additional dances should be introduced only when their terminology, timing, movement rules, and reference material are sufficiently labelled.

### AI teacher experience

The AI teacher should be able to:

- Recommend an appropriate next lesson.
- Demonstrate a move through video and skeleton playback.
- Break a movement into counts and phases.
- Observe a student attempt.
- Identify meaningful differences from validated references.
- Explain the most important correction in plain language.
- Recommend a targeted exercise.
- Track improvement over repeated attempts.
- Adjust difficulty based on demonstrated ability.

The initial AI teacher should select and explain validated knowledge. It should not invent unsupported dance technique or pretend certainty when pose visibility is poor.

### Evaluation

AI instruction should be tested against teacher judgement using a labelled evaluation set. Important measures include:

- Correct identification of the performed move.
- Timing and sequence accuracy.
- Agreement with teachers on important errors.
- Rate of false or misleading corrections.
- Improvement across repeated student attempts.
- Student understanding and usefulness ratings.

### Phase 3 completion criteria

- The knowledge library has a consistent schema and expert-reviewed content.
- The AI can select lessons appropriate to a student's level.
- Feedback is traceable to a reference movement or teaching rule.
- The system communicates uncertainty when video or pose quality is insufficient.
- Teacher evaluation demonstrates that feedback is useful and not routinely misleading.

---

## Phase 4 — AI-assisted choreography

### Goal

Use the validated movement library to create coherent combinations and dance routines that match a dancer's goals, ability, and selected music.

### Choreography inputs

The user should be able to choose:

- Dance style.
- Solo styling or partner work.
- Leader and follower roles where applicable.
- Skill level.
- Routine duration.
- Song or audio track.
- BPM and musical structure.
- Desired mood, energy, or performance style.
- Available space and physical constraints.
- Moves to include or avoid.

### Generation approach

The first choreography engine should assemble validated moves and transitions rather than generate unconstrained body motion.

A routine should include:

- Move names and roles.
- Counts and timing.
- Transition rules.
- Phrase and section structure.
- Difficulty progression.
- Reference video or skeleton segments.
- A teachable breakdown and practice order.

Generated combinations must respect:

- Physically possible transitions.
- Dance-style rules and timing.
- Partner compatibility.
- Skill-level constraints.
- Safe movement and available space.
- Musical phrasing rather than BPM alone.

### Human review and learning loop

- Teachers can review, edit, and publish generated routines.
- Dancers can replace moves they cannot or do not want to perform.
- User and teacher feedback improves transition ranking over time.
- Generated routines retain a record of their source moves, rules, and revisions.

### Phase 4 completion criteria

- Generated routines use valid moves and transitions from the curated library.
- Timing and roles remain internally consistent.
- A dancer can preview, learn, practise, and record the routine inside DanceSage.
- Teachers can edit generated choreography without rebuilding it from scratch.
- Human evaluation shows that routines are coherent, teachable, safe, and stylistically appropriate.

---

## Explicitly outside the current roadmap

- AI music or song production.
- A full DanceSage social feed.
- Replacing qualified teachers in safety-critical or advanced instruction.
- Unrestricted generation of movements without validated dance constraints.
- Building separate infrastructure for every social platform before standard sharing is proven.

## Immediate priorities

1. Finish and harden the Phase 1 recording and retrieval workflow.
2. Improve pose stability, confidence handling, and partner identity tracking.
3. Add a reliable 9:16 video export with optional skeleton rendering.
4. Share exports through the native iOS share sheet and test the TikTok workflow.
5. Confirm that saved pose data contains the metadata needed for future comparison.
6. Test Phase 1 with real dancers before introducing Phase 2 accounts and backend services.
