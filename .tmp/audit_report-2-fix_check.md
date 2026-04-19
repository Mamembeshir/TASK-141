# GreenGate Previous-Issues Re-Review (Static)

Reviewed only the previously reported issues from the last audit, using static code inspection.

## Verdict
- **All three previously listed issues are fixed in current code.**
- No remaining open findings from that specific prior issue list.

## Issue-by-Issue Status

1) **High: Ticket issuance UI called internal raw-actor overload**
- **Status:** Fixed
- **What changed:** Event ticket generation now requires authenticated `User` and calls the role-checked overload.
- **Evidence:**
  - UI now guards signed-in actor: `GreenGate/ViewControllers/Tickets/EventDetailViewController.swift:252`
  - UI now calls typed API: `GreenGate/ViewControllers/Tickets/EventDetailViewController.swift:257`
  - Typed API enforces role: `GreenGate/Services/TicketService.swift:86`
  - Raw `actorID` overload usage appears limited to service internal + tests: `GreenGate/Services/TicketService.swift:90`, `GreenGateTests/UnitTests/TicketServiceTests.swift:107`

2) **High: Signature-failure check-in wrote data without matching audit row**
- **Status:** Fixed
- **What changed:** Signature-failure catch branch now logs check-in audit before save.
- **Evidence:**
  - Invalid check-in log insert: `GreenGate/Services/TicketService.swift:145`
  - Added audit log in same branch: `GreenGate/Services/TicketService.swift:147`
  - Save after both writes: `GreenGate/Services/TicketService.swift:151`

3) **Medium: System actor fallback in production ticket generation path**
- **Status:** Fixed
- **What changed:** Production UI path removed `systemActorID` fallback and now blocks when user is not signed in.
- **Evidence:**
  - Auth guard + error return: `GreenGate/ViewControllers/Tickets/EventDetailViewController.swift:252`
  - No fallback usage in that flow anymore: `GreenGate/ViewControllers/Tickets/EventDetailViewController.swift:252`

## Static Boundary Note
- This re-check did **not** run the app or tests.
- Conclusion is based on static code evidence only.
