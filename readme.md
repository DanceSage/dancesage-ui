**Dance Sage - App Scope & Features**

---

**Core Concept:**
AI-powered dance learning and choreography app for Latin dances (Salsa, Bachata, Merengue, Kizomba) with pose detection, move analysis, and personalized feedback.

---

**Key Features:**

**1. Dual Mode System:**
- **Sage Mode (Teacher):** Record and create reference choreography
- **Student Mode:** Practice and receive real-time feedback

**2. Teacher/Sage Mode:**
- Record dance sequences to create reference patterns
- Upload clips from YouTube/TikTok as reference material
- System stores keypoint sequences as "ground truth"

**3. Student Mode:**
- Record practice sessions
- Real-time comparison against selected reference style
- Visual feedback (green = accurate, red = needs improvement)
- Per-body-part accuracy scoring

**4. AI Choreography Generator (Future):**
- "Show me dance moves" - AI generates stick figure performing suggested moves
- Based on student's training history and ability level
- Personalized difficulty scaling

**5. Adaptive Learning (Future):**
- "Teach me new moves" - suggests progressions based on student ability
- Tracks improvement over time
- Difficulty adapts to student's mastery

**6. Partner Work Detection (Advanced):**
- Detect and analyze two-person dance patterns
- Synchronization scoring for partner dances
- Specific to Salsa, Bachata, Merengue, Kizomba styles

---

**Technical Stack:**

**Frontend (iOS/Swift):**
- MediaPipe for pose detection
- Real-time keypoint extraction
- Firebase Authentication
- Visual feedback overlay

**Backend (Python ML):**
- REST API for keypoint processing
- ML models for move comparison & scoring
- Pattern recognition for dance styles
- Choreography generation algorithm
- Video processing for YouTube/TikTok extraction
- Database for storing reference patterns & student history

**ML Techniques:**
- Dynamic Time Warping (DTW) for sequence matching
- Deep learning for move classification
- Generative models for choreography creation
- Time-series analysis for rhythm/timing
- Multi-person pose tracking for partner work

---

**MVP Priority:**
1. ✅ Auth & Landing UI
2. Teacher mode recording
3. Student mode recording
4. Backend API for keypoint storage
5. Basic move comparison & feedback
6. (Future) AI choreography & partner detection
# DanceSage iOS

DanceSage has two primary paths:

- **Find a Dance Tonight** searches the DanceSage API for date-specific salsa,
  bachata, and Latin events. Every result links to the source used to verify it.
- **Practice & Improve** keeps the existing live recording, video import, skeleton
  processing, playback, and local recording library.

Users can bookmark an event locally. DanceSage stores watched events on the
iPhone and schedules a reminder two hours before the event. Production
organizer-change and cancellation alerts still require a server-side scheduled
monitor plus APNs; the app does not claim that a local reminder provides this.

## API configuration

Debug builds default to `http://127.0.0.1:8000`. For device and release builds,
set the Xcode build setting `DANCE_SAGE_API_BASE_URL` to the HTTPS base URL of
the deployed `dancesage-api` service. API keys belong only on the server.
