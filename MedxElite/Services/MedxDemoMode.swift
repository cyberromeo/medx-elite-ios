#if DEBUG
import Foundation

// MARK: - Demo mode
//
// A DEBUG-only, fully offline copy of the backend, so a CI job can launch the app in the iOS
// Simulator and screenshot every screen without a login, a password or a network round trip to
// Firebase. Nothing here exists in a Release build (the `#else` at the bottom is a two-line stub
// so call sites need no `#if`).
//
// Switch it on with the launch argument `-medxDemo YES` (or the environment variable
// `MEDX_DEMO=1`, which `simctl launch` passes as `SIMCTL_CHILD_MEDX_DEMO=1`). Add
// `-medxDemoSignedOut YES` to land on the profile picker instead of Home.
//
// How it works: every Firestore, Identity Toolkit and Secure Token request in this app goes
// through `URLSession.shared`, so one registered `URLProtocol` answers all of them from an
// in-memory store shaped exactly like the Firestore REST API. Image, flashcard and video CDNs
// are not intercepted and load for real. Writes land in the same store, so a sitting you finish,
// a bookmark you toggle or a tracker cell you tick shows up on the next read, until relaunch.
//
// The signed-in state needs no change to `AuthService`: `install()` runs before
// `AuthService.shared` is first touched and writes a far-future session where
// `loadSavedSession()` reads it.

enum MedxDemoMode {
    /// True when the process was launched with `-medxDemo YES` or `MEDX_DEMO=1`.
    static var isOn: Bool {
        if UserDefaults.standard.bool(forKey: "medxDemo") { return true }
        return ProcessInfo.processInfo.environment["MEDX_DEMO"] == "1"
    }

    /// `-medxDemoSignedOut YES`: start on the profile picker (signing in there still works,
    /// with any password, and never leaves the device).
    static var startsSignedOut: Bool {
        UserDefaults.standard.bool(forKey: "medxDemoSignedOut")
    }

    static let interceptedHosts: Set<String> = [
        "firestore.googleapis.com",
        "identitytoolkit.googleapis.com",
        "securetoken.googleapis.com"
    ]

    static let idToken = "medx-demo-id-token"
    static let refreshToken = "medx-demo-refresh-token"
    static var profile: Profile { Profile.quantumGuy }

    /// Call first thing in `MedxEliteApp.init()`, before anything touches `AuthService.shared`.
    static func install() {
        guard isOn else { return }
        URLProtocol.registerClass(MedxDemoURLProtocol.self)
        seedDefaults()
        // Before anything touches `VideoDownloadStore.shared`, which reads the folder once.
        if UserDefaults.standard.string(forKey: "medxScreen") == "player-offline" {
            MedxOfflineFixture.install()
        }
        if startsSignedOut {
            UserDefaults.standard.removeObject(forKey: "medx.auth.session")
        } else {
            seedSession()
        }
        print("[MedxDemo] demo mode on: Firestore, sign-in and token refresh are answered offline")
    }

    private static func seedSession() {
        let demoProfile = profile
        let session = AuthSession(
            idToken: idToken,
            refreshToken: refreshToken,
            uid: demoProfile.uid,
            email: demoProfile.email,
            profileId: demoProfile.id,
            expirationDate: Date().addingTimeInterval(60 * 60 * 24 * 365 * 5)
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "medx.auth.session")
        }
    }

    /// The Home countdown and the daily goal ring, so they read like a student three weeks out.
    private static func seedDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "medx.exam.date") == nil {
            let start = Calendar.current.startOfDay(for: Date())
            let exam = Calendar.current.date(byAdding: .day, value: 22, to: start) ?? start
            defaults.set(exam.timeIntervalSince1970, forKey: "medx.exam.date")
        }
        if defaults.object(forKey: "medx.exam.name") == nil {
            defaults.set("FMGE", forKey: "medx.exam.name")
        }
        if defaults.object(forKey: "medx.goal.daily") == nil {
            defaults.set(60, forKey: "medx.goal.daily")
        }
    }
}

// MARK: - The URL protocol

final class MedxDemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return MedxDemoMode.interceptedHosts.contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let incoming = request
        let answer = MedxDemoBackend.shared.respond(to: incoming)
        let url = incoming.url ?? URL(string: "https://firestore.googleapis.com")!
        let headers = ["Content-Type": "application/json; charset=UTF-8"]
        if let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Values

/// A Firestore value, typed, so fixtures never depend on how `Any` casts a `Bool` or an `Int`.
enum MedxDemoValue: Sendable {
    case s(String)
    case i(Int)
    case d(Double)
    case b(Bool)
    case t(Date)
    case a([MedxDemoValue])
    case m([String: MedxDemoValue])
    case null

    var firestore: [String: Any] {
        switch self {
        case .s(let value):
            return ["stringValue": value]
        case .i(let value):
            return ["integerValue": String(value)]
        case .d(let value):
            return ["doubleValue": value]
        case .b(let value):
            return ["booleanValue": value]
        case .t(let value):
            return ["timestampValue": MedxDemoClock.timestamp(value)]
        case .a(let values):
            let mapped: [[String: Any]] = values.map { $0.firestore }
            let inner: [String: Any] = ["values": mapped]
            return ["arrayValue": inner]
        case .m(let fields):
            let inner: [String: Any] = ["fields": MedxDemoValue.fields(fields)]
            return ["mapValue": inner]
        case .null:
            return ["nullValue": NSNull()]
        }
    }

    static func fields(_ fields: [String: MedxDemoValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in fields {
            out[key] = value.firestore
        }
        return out
    }

    static func strings(_ values: [String]) -> MedxDemoValue {
        .a(values.map { MedxDemoValue.s($0) })
    }
}

enum MedxDemoClock {
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// The plain ISO form the app itself writes into `finishedAt`, `bookmarkedAt` and friends.
    /// No fractional seconds: `ISO8601DateFormatter()` with default options cannot read them.
    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// djb2, because `hashValue` is reseeded every launch and fixtures must not move between runs.
enum MedxDemoHash {
    static func value(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }

    static func int(_ text: String, in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(value(text) % span)
    }

    static func hex(_ text: String, length: Int) -> String {
        var out = ""
        var round = 0
        while out.count < length {
            let chunk = String(value("\(text)#\(round)"), radix: 16)
            out += chunk
            round += 1
        }
        return String(out.prefix(length))
    }
}

// MARK: - Question content

/// One authored MCQ. `correct` is the 0-based index of the right option.
struct MedxDemoMCQ: Sendable {
    let subject: String
    let stem: String
    let options: [String]
    let correct: Int
    let explanation: String
}

enum MedxDemoQuestions {
    /// The featured module: a full, correct FMGE-style Microbiology sitting.
    static let microCocci: [MedxDemoMCQ] = [
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "A 24-year-old woman develops high fever, hypotension, a diffuse erythematous rash and later desquamation of the palms during menstruation while using a tampon. The toxin most likely responsible is:",
            options: ["TSST-1", "Exfoliative toxin A", "Panton-Valentine leukocidin", "Streptolysin O"],
            correct: 0,
            explanation: "<p><b>Toxic shock syndrome toxin-1 (TSST-1)</b> of <i>Staphylococcus aureus</i> is a <b>superantigen</b>. It cross-links <b>MHC class II</b> with the T-cell receptor outside the peptide groove, causing <b>massive cytokine release</b> and shock. Menstrual TSS is classically linked to <b>tampon use</b>.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Sensitivity to bacitracin is used in the laboratory to identify:",
            options: ["Streptococcus agalactiae", "Streptococcus pyogenes", "Enterococcus faecalis", "Streptococcus pneumoniae"],
            correct: 1,
            explanation: "<p><b>Group A Streptococcus (<i>S. pyogenes</i>)</b> is bacitracin sensitive. Group B (<i>S. agalactiae</i>) is bacitracin resistant and CAMP positive.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "A beta-haemolytic streptococcus isolated from a neonate with meningitis is bacitracin resistant, hydrolyses hippurate and gives a positive CAMP test. The organism is:",
            options: ["Streptococcus pyogenes", "Streptococcus agalactiae", "Viridans streptococci", "Streptococcus gallolyticus (bovis)"],
            correct: 1,
            explanation: "<p><b><i>S. agalactiae</i> (Group B)</b> is the leading cause of neonatal sepsis and meningitis. CAMP positive, hippurate hydrolysis positive and bacitracin resistant.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "An alpha-haemolytic, lancet-shaped Gram-positive diplococcus is optochin sensitive and bile soluble. It is:",
            options: ["Streptococcus mutans", "Enterococcus faecalis", "Streptococcus pneumoniae", "Streptococcus mitis"],
            correct: 2,
            explanation: "<p><b>Pneumococcus</b> is optochin sensitive and bile soluble (autolysis via amidase). Viridans streptococci are optochin resistant and bile insoluble.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "A coagulase-negative staphylococcus causing urinary tract infection in a sexually active young woman is resistant to novobiocin. The organism is:",
            options: ["Staphylococcus epidermidis", "Staphylococcus saprophyticus", "Staphylococcus aureus", "Staphylococcus haemolyticus"],
            correct: 1,
            explanation: "<p><b><i>S. saprophyticus</i></b> is novobiocin resistant and is the second commonest cause of UTI in young sexually active women. <i>S. epidermidis</i> is novobiocin sensitive.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Which of the following grows in the presence of 6.5% NaCl and 40% bile and hydrolyses aesculin?",
            options: ["Enterococcus faecalis", "Streptococcus bovis", "Streptococcus pyogenes", "Streptococcus pneumoniae"],
            correct: 0,
            explanation: "<p><b>Enterococci</b> grow in 6.5% NaCl, 40% bile, at 10 to 45 °C and at pH 9.6. <i>S. bovis</i> is bile aesculin positive but does not grow in 6.5% NaCl.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Staphylococcal scalded skin syndrome is caused by a toxin that cleaves:",
            options: ["Desmoglein-1", "Desmoglein-3", "Collagen type VII", "Bullous pemphigoid antigen 180"],
            correct: 0,
            explanation: "<p>The <b>exfoliative (epidermolytic) toxins</b> A and B are serine proteases that cleave <b>desmoglein-1</b>, splitting the epidermis at the stratum granulosum. Mucosa is spared.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Acute rheumatic fever follows Group A streptococcal infection of the:",
            options: ["Skin only", "Pharynx only", "Both skin and pharynx", "Urinary tract"],
            correct: 1,
            explanation: "<p><b>Rheumatic fever follows only pharyngitis.</b> Post-streptococcal glomerulonephritis can follow either pharyngitis or pyoderma.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Methicillin resistance in Staphylococcus aureus is due to:",
            options: ["Beta-lactamase production", "Altered penicillin-binding protein PBP2a encoded by mecA", "Efflux pumps", "Altered D-Ala-D-Ala target"],
            correct: 1,
            explanation: "<p><b>MRSA</b> carries <b>mecA</b> on SCCmec, which encodes <b>PBP2a</b> with low affinity for beta-lactams. Altered D-Ala-D-Lac is the mechanism of vancomycin resistance (VRE).</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "Food poisoning with vomiting 2 hours after eating custard at a wedding is most likely caused by:",
            options: ["Clostridium perfringens", "Bacillus cereus (diarrhoeal type)", "Staphylococcus aureus", "Salmonella Typhimurium"],
            correct: 2,
            explanation: "<p><b>Staphylococcal food poisoning</b> is due to a preformed, heat-stable enterotoxin, so the incubation period is short: <b>1 to 6 hours</b>, with prominent vomiting. Custard, cream and milk products are typical.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "The Quellung reaction demonstrates the capsule of:",
            options: ["Streptococcus pneumoniae", "Staphylococcus aureus", "Enterococcus faecalis", "Streptococcus pyogenes"],
            correct: 0,
            explanation: "<p>Capsular swelling with type-specific antiserum (<b>Neufeld Quellung reaction</b>) is classically used for <i>S. pneumoniae</i>; it also works for <i>H. influenzae</i> and <i>Klebsiella</i>.</p>"
        ),
        MedxDemoMCQ(
            subject: "Microbiology",
            stem: "The M protein of Streptococcus pyogenes acts mainly by:",
            options: ["Inhibiting phagocytosis", "Lysing red cells", "Spreading through tissue planes", "Dissolving fibrin clots"],
            correct: 0,
            explanation: "<p><b>M protein</b> is the major virulence factor: it is <b>antiphagocytic</b> and its antibodies are type specific. Hyaluronidase spreads infection and streptokinase lyses fibrin.</p>"
        )
    ]

    static let pathology: [MedxDemoMCQ] = [
        MedxDemoMCQ(subject: "Pathology", stem: "Which of the following is a feature of irreversible cell injury?", options: ["Cellular swelling", "Fatty change", "Karyorrhexis", "Detachment of ribosomes"], correct: 2, explanation: "<p>Nuclear changes (<b>pyknosis, karyorrhexis, karyolysis</b>) and severe mitochondrial damage mark the point of no return. Swelling, fatty change and ribosome detachment are reversible.</p>"),
        MedxDemoMCQ(subject: "Pathology", stem: "Psammoma bodies are characteristically seen in:", options: ["Follicular carcinoma thyroid", "Papillary carcinoma thyroid", "Medullary carcinoma thyroid", "Anaplastic carcinoma thyroid"], correct: 1, explanation: "<p><b>Papillary carcinoma thyroid</b>, along with serous cystadenocarcinoma ovary and meningioma. They are concentric laminated calcifications (dystrophic).</p>"),
        MedxDemoMCQ(subject: "Pathology", stem: "Reed-Sternberg cells of classical Hodgkin lymphoma are positive for:", options: ["CD15 and CD30", "CD20 and CD45", "CD3 and CD5", "CD10 and BCL6"], correct: 0, explanation: "<p>Classical RS cells are <b>CD15+ and CD30+</b>, CD45 negative. The nodular lymphocyte-predominant type (popcorn cells) is CD20+ and CD15/CD30 negative.</p>"),
        MedxDemoMCQ(subject: "Pathology", stem: "The type of necrosis seen in an infarct of the brain is:", options: ["Coagulative", "Liquefactive", "Caseous", "Fibrinoid"], correct: 1, explanation: "<p>Hypoxic death in the CNS gives <b>liquefactive necrosis</b>. Infarcts of solid organs elsewhere are coagulative.</p>"),
        MedxDemoMCQ(subject: "Pathology", stem: "A \"starry sky\" appearance on lymph node histology is typical of:", options: ["Follicular lymphoma", "Burkitt lymphoma", "Mantle cell lymphoma", "Hairy cell leukaemia"], correct: 1, explanation: "<p><b>Burkitt lymphoma</b>: sheets of medium-sized cells with tingible-body macrophages forming the stars. t(8;14) with MYC activation.</p>")
    ]

    static let pharmacology: [MedxDemoMCQ] = [
        MedxDemoMCQ(subject: "Pharmacology", stem: "Drug of choice for typical absence seizures in a child is:", options: ["Phenytoin", "Carbamazepine", "Ethosuximide", "Phenobarbitone"], correct: 2, explanation: "<p><b>Ethosuximide</b> blocks T-type calcium channels in the thalamus. Carbamazepine and phenytoin can worsen absence seizures.</p>"),
        MedxDemoMCQ(subject: "Pharmacology", stem: "The specific antidote for heparin overdose is:", options: ["Vitamin K", "Protamine sulphate", "Fresh frozen plasma", "Idarucizumab"], correct: 1, explanation: "<p><b>Protamine sulphate</b>, a basic protein, neutralises the acidic heparin. Idarucizumab reverses dabigatran; vitamin K reverses warfarin.</p>"),
        MedxDemoMCQ(subject: "Pharmacology", stem: "\"Red man syndrome\" on rapid intravenous infusion is associated with:", options: ["Vancomycin", "Rifampicin", "Clofazimine", "Linezolid"], correct: 0, explanation: "<p>Rapid infusion of <b>vancomycin</b> causes non-immunological histamine release with flushing of the face and upper body. Slow the infusion.</p>"),
        MedxDemoMCQ(subject: "Pharmacology", stem: "Gray baby syndrome in neonates is caused by:", options: ["Tetracycline", "Chloramphenicol", "Sulphonamides", "Gentamicin"], correct: 1, explanation: "<p>Neonates lack <b>glucuronyl transferase</b>, so <b>chloramphenicol</b> accumulates: vomiting, hypothermia, ashen grey cyanosis and cardiovascular collapse.</p>")
    ]

    static let general: [MedxDemoMCQ] = [
        MedxDemoMCQ(subject: "Anatomy", stem: "A fracture of the surgical neck of the humerus is most likely to injure the:", options: ["Radial nerve", "Axillary nerve", "Musculocutaneous nerve", "Ulnar nerve"], correct: 1, explanation: "<p>The <b>axillary nerve</b> winds round the surgical neck with the posterior circumflex humeral artery: deltoid weakness and loss of sensation over the regimental badge area.</p>"),
        MedxDemoMCQ(subject: "Physiology", stem: "Normal glomerular filtration rate in a healthy adult is approximately:", options: ["60 mL/min", "125 mL/min", "250 mL/min", "650 mL/min"], correct: 1, explanation: "<p>GFR is about <b>125 mL/min</b> (180 L/day). Renal plasma flow is about 625 to 650 mL/min, giving a filtration fraction near 20%.</p>"),
        MedxDemoMCQ(subject: "Biochemistry", stem: "The coenzyme required for transamination reactions is derived from:", options: ["Thiamine", "Riboflavin", "Pyridoxine", "Niacin"], correct: 2, explanation: "<p><b>Pyridoxal phosphate (vitamin B6)</b> is the coenzyme for aminotransferases, decarboxylases and ALA synthase.</p>"),
        MedxDemoMCQ(subject: "Community Medicine", stem: "A vaccine vial monitor shows the inner square the same colour as the outer circle. The correct action is:", options: ["Use the vial", "Use it within 24 hours", "Discard the vial", "Shake test before use"], correct: 2, explanation: "<p>Once the inner square <b>matches or is darker</b> than the outer circle, the discard point has been reached. Do not use the vial.</p>"),
        MedxDemoMCQ(subject: "Ophthalmology", stem: "A cherry-red spot at the macula with a pale retina after sudden painless loss of vision suggests:", options: ["Central retinal vein occlusion", "Central retinal artery occlusion", "Retinal detachment", "Vitreous haemorrhage"], correct: 1, explanation: "<p>In <b>CRAO</b> the ischaemic, opaque retina contrasts with the intact choroidal circulation seen through the thin fovea.</p>"),
        MedxDemoMCQ(subject: "ENT", stem: "The commonest site of epistaxis is:", options: ["Woodruff's plexus", "Little's area", "Inferior turbinate", "Roof of the nose"], correct: 1, explanation: "<p><b>Little's area</b> (Kiesselbach's plexus) on the anteroinferior septum accounts for about 90% of nosebleeds, especially in children and young adults.</p>"),
        MedxDemoMCQ(subject: "Medicine", stem: "The most common cause of community-acquired pneumonia in adults is:", options: ["Staphylococcus aureus", "Klebsiella pneumoniae", "Streptococcus pneumoniae", "Mycoplasma pneumoniae"], correct: 2, explanation: "<p><b>Pneumococcus</b> remains the commonest identified cause of CAP across age groups.</p>"),
        MedxDemoMCQ(subject: "Surgery", stem: "Charcot's triad of ascending cholangitis consists of:", options: ["Fever, jaundice and right upper quadrant pain", "Fever, jaundice and hypotension", "Pain, vomiting and distension", "Jaundice, palpable gallbladder and weight loss"], correct: 0, explanation: "<p><b>Fever with rigors, jaundice and RUQ pain.</b> Add hypotension and confusion for Reynolds' pentad.</p>"),
        MedxDemoMCQ(subject: "Obstetrics", stem: "The drug of choice for the control of convulsions in eclampsia is:", options: ["Diazepam", "Phenytoin", "Magnesium sulphate", "Labetalol"], correct: 2, explanation: "<p><b>Magnesium sulphate</b> (Pritchard or Zuspan regimen). Monitor knee jerks, respiratory rate and urine output; calcium gluconate is the antidote.</p>"),
        MedxDemoMCQ(subject: "Pediatrics", stem: "Koplik spots are pathognomonic of:", options: ["Rubella", "Measles", "Scarlet fever", "Chickenpox"], correct: 1, explanation: "<p><b>Koplik spots</b>, grey-white spots on the buccal mucosa opposite the lower molars, appear in the prodrome of <b>measles</b> before the rash.</p>"),
        MedxDemoMCQ(subject: "Forensic Medicine", stem: "A smell of bitter almonds at autopsy suggests poisoning with:", options: ["Organophosphates", "Hydrocyanic acid", "Phosphorus", "Arsenic"], correct: 1, explanation: "<p><b>Cyanide</b> gives a bitter almond odour and bright red post-mortem staining. Garlic odour suggests phosphorus or arsenic.</p>"),
        MedxDemoMCQ(subject: "Dermatology", stem: "Pinpoint bleeding on scraping a scaly plaque (Auspitz sign) is seen in:", options: ["Lichen planus", "Psoriasis", "Pityriasis rosea", "Pemphigus vulgaris"], correct: 1, explanation: "<p><b>Psoriasis</b>: removal of scales exposes the thinned suprapapillary plate over dilated capillaries.</p>"),
        MedxDemoMCQ(subject: "Psychiatry", stem: "The drug of choice for prophylaxis in bipolar disorder is:", options: ["Haloperidol", "Lithium", "Fluoxetine", "Clonazepam"], correct: 1, explanation: "<p><b>Lithium</b> reduces relapse and suicide risk. Monitor serum levels, thyroid and renal function.</p>"),
        MedxDemoMCQ(subject: "Orthopedics", stem: "The nerve most commonly injured in a supracondylar fracture of the humerus in children is the:", options: ["Radial nerve", "Ulnar nerve", "Anterior interosseous nerve", "Axillary nerve"], correct: 2, explanation: "<p>The <b>anterior interosseous branch of the median nerve</b> is most often injured (extension type, posterolateral displacement): inability to make the OK sign.</p>"),
        MedxDemoMCQ(subject: "Anesthesia", stem: "The inhalational agent of choice for induction in children is:", options: ["Isoflurane", "Desflurane", "Sevoflurane", "Halothane"], correct: 2, explanation: "<p><b>Sevoflurane</b> is sweet smelling, non-irritant and gives a smooth, rapid induction. Desflurane irritates the airway.</p>"),
        MedxDemoMCQ(subject: "Radiology", stem: "The investigation of choice in suspected acute subarachnoid haemorrhage is:", options: ["MRI brain", "Non-contrast CT head", "Lumbar puncture", "Cerebral angiography"], correct: 1, explanation: "<p><b>NCCT head</b> is most sensitive in the first hours. A negative scan with strong suspicion is followed by LP for xanthochromia.</p>"),
        MedxDemoMCQ(subject: "Gynaecology", stem: "The most common site of endometriosis is the:", options: ["Ovary", "Pouch of Douglas", "Umbilicus", "Cervix"], correct: 0, explanation: "<p>The <b>ovary</b> is the commonest site; endometriomas form \"chocolate cysts\".</p>")
    ]

    static func pool(for subject: String) -> [MedxDemoMCQ] {
        switch subject {
        case "Microbiology": return microCocci
        case "Pathology": return pathology
        case "Pharmacology": return pharmacology
        default:
            let matching = general.filter { $0.subject == subject }
            return matching.isEmpty ? general : matching + general
        }
    }

    /// One `Question` map, in the field names `Question.init(from:)` reads.
    static func question(_ mcq: MedxDemoMCQ, id: Int, number: Int, reference: String?) -> [String: MedxDemoValue] {
        let labels = ["A", "B", "C", "D", "E"]
        var options: [MedxDemoValue] = []
        for (index, text) in mcq.options.enumerated() {
            let option: [String: MedxDemoValue] = [
                "id": .i(id * 10 + index + 1),
                "label": .s(labels[min(index, labels.count - 1)]),
                "text": .s(text),
                "correct": .b(index == mcq.correct)
            ]
            options.append(.m(option))
        }
        var fields: [String: MedxDemoValue] = [
            "id": .i(id),
            "number": .i(number),
            "html": .s("<p>\(mcq.stem)</p>"),
            "plain": .s(mcq.stem),
            "options": .a(options),
            "correctIds": .a([.i(id * 10 + mcq.correct + 1)]),
            "explanation": .s(mcq.explanation)
        ]
        if let reference {
            fields["reference"] = .s(reference)
        }
        return fields
    }
}

// MARK: - Catalogue

/// One module either bank can resolve, kept so every id a list shows opens in the runner.
struct MedxDemoModule: Sendable {
    let id: String
    let name: String
    let subject: String
    let subjectId: Int
    let chapter: String
    let chapterId: Int
    let questionCount: Int
    let featured: Bool
}

struct MedxDemoSubjectSpec: Sendable {
    let name: String
    let slug: String
    let moduleTarget: Int
    let chapters: [String]
    /// Real module titles per chapter, where a subject has them; otherwise parts are numbered.
    let topics: [String: [String]]
}

enum MedxDemoCatalog {
    static let featuredModuleName = "Gram-Positive Cocci: Staphylococcus & Streptococcus"

    static let ariseSubjects: [MedxDemoSubjectSpec] = [
        MedxDemoSubjectSpec(name: "Anatomy", slug: "anatomy", moduleTarget: 72, chapters: ["Upper Limb", "Lower Limb", "Thorax", "Abdomen & Pelvis", "Head & Neck", "Neuroanatomy", "Embryology", "Histology"], topics: [:]),
        MedxDemoSubjectSpec(name: "Physiology", slug: "physiology", moduleTarget: 52, chapters: ["General & Nerve-Muscle", "Blood", "Cardiovascular", "Respiratory", "Renal", "Endocrine", "CNS"], topics: [:]),
        MedxDemoSubjectSpec(name: "Biochemistry", slug: "biochemistry", moduleTarget: 48, chapters: ["Carbohydrates", "Lipids", "Proteins & Amino Acids", "Enzymes", "Vitamins", "Molecular Biology"], topics: [:]),
        MedxDemoSubjectSpec(name: "Pathology", slug: "pathology", moduleTarget: 28, chapters: ["General Pathology", "Hematology", "Systemic Pathology"], topics: [
            "General Pathology": ["Cell Injury & Adaptation", "Necrosis & Apoptosis", "Acute & Chronic Inflammation", "Healing & Repair", "Hemodynamic Disorders", "Genetic Disorders", "Immunopathology & Amyloidosis", "Neoplasia I", "Neoplasia II"],
            "Hematology": ["Microcytic Anemias", "Megaloblastic Anemia", "Hemolytic Anemias", "Leukemias", "Lymphomas", "Platelet & Coagulation Disorders", "Blood Banking"],
            "Systemic Pathology": ["Cardiovascular", "Respiratory", "Kidney", "GIT", "Liver & Biliary", "CNS", "Bone & Soft Tissue", "Breast", "Male Genital", "Female Genital", "Endocrine", "Skin"]
        ]),
        MedxDemoSubjectSpec(name: "Pharmacology", slug: "pharmacology", moduleTarget: 64, chapters: ["General Pharmacology", "Autonomic Nervous System", "Cardiovascular Drugs", "CNS Drugs", "Chemotherapy", "Endocrine Drugs", "Autacoids & Respiratory"], topics: [:]),
        MedxDemoSubjectSpec(name: "Microbiology", slug: "microbiology", moduleTarget: 36, chapters: ["General Microbiology", "Immunology", "Systemic Bacteriology", "Virology", "Mycology", "Parasitology"], topics: [
            "General Microbiology": ["History & Microscopy", "Sterilisation & Disinfection", "Culture Media & Methods", "Bacterial Genetics", "Bacterial Structure & Growth"],
            "Immunology": ["Innate Immunity", "Antigens & Antibodies", "Hypersensitivity", "Complement", "Transplant & Tumour Immunology"],
            "Systemic Bacteriology": [MedxDemoCatalog.featuredModuleName, "Pneumococcus & Enterococcus", "Neisseria", "Corynebacterium", "Bacillus & Clostridium", "Enterobacteriaceae", "Vibrio", "Mycobacteria", "Spirochetes", "Rickettsia & Chlamydia"],
            "Virology": ["General Virology", "Herpesviruses", "Hepatitis Viruses", "HIV", "Arboviruses", "Myxoviruses", "Picornaviruses"],
            "Mycology": ["Superficial Mycoses", "Subcutaneous Mycoses", "Systemic & Opportunistic Fungi"],
            "Parasitology": ["Amoeba & Giardia", "Malaria", "Leishmania & Trypanosoma", "Cestodes", "Trematodes", "Nematodes"]
        ]),
        MedxDemoSubjectSpec(name: "Forensic Medicine", slug: "forensic-medicine", moduleTarget: 34, chapters: ["Thanatology", "Injuries", "Asphyxia", "Toxicology", "Sexual Offences", "Legal Procedures"], topics: [:]),
        MedxDemoSubjectSpec(name: "Community Medicine", slug: "community-medicine", moduleTarget: 80, chapters: ["Epidemiology", "Biostatistics", "Communicable Diseases", "Non-Communicable Diseases", "Nutrition", "Health Programmes", "Environment & Occupational Health", "Demography & Family Planning"], topics: [:]),
        MedxDemoSubjectSpec(name: "ENT", slug: "ent", moduleTarget: 40, chapters: ["Ear", "Nose & PNS", "Pharynx", "Larynx", "Head & Neck Tumours"], topics: [:]),
        MedxDemoSubjectSpec(name: "Ophthalmology", slug: "ophthalmology", moduleTarget: 44, chapters: ["Cornea", "Lens", "Glaucoma", "Uvea", "Retina", "Neuro-ophthalmology", "Squint"], topics: [:]),
        MedxDemoSubjectSpec(name: "Medicine", slug: "medicine", moduleTarget: 100, chapters: ["Cardiology", "Pulmonology", "Gastroenterology", "Nephrology", "Neurology", "Endocrinology", "Hematology", "Rheumatology", "Infectious Diseases"], topics: [:]),
        MedxDemoSubjectSpec(name: "Surgery", slug: "surgery", moduleTarget: 96, chapters: ["General Surgery", "Trauma", "GI Surgery", "Hepatobiliary", "Urology", "Breast & Endocrine", "Vascular", "Neurosurgery", "Plastic & Burns"], topics: [:]),
        MedxDemoSubjectSpec(name: "Obstetrics", slug: "obstetrics", moduleTarget: 46, chapters: ["Physiology of Pregnancy", "Antenatal Care", "Labour", "Medical Disorders in Pregnancy", "Obstetric Haemorrhage", "Puerperium"], topics: [:]),
        MedxDemoSubjectSpec(name: "Gynaecology", slug: "gynaecology", moduleTarget: 38, chapters: ["Menstrual Disorders", "Infertility", "Contraception", "Gynaecological Oncology", "Genital Infections", "Prolapse"], topics: [:]),
        MedxDemoSubjectSpec(name: "Pediatrics", slug: "pediatrics", moduleTarget: 54, chapters: ["Growth & Development", "Neonatology", "Nutrition", "Immunisation", "Infections", "Genetics", "Pediatric Cardiology"], topics: [:]),
        MedxDemoSubjectSpec(name: "Orthopedics", slug: "orthopedics", moduleTarget: 36, chapters: ["Fractures", "Bone Tumours", "Bone & Joint Infections", "Spine", "Sports Injuries", "Peripheral Nerve Injuries"], topics: [:]),
        MedxDemoSubjectSpec(name: "Dermatology", slug: "dermatology", moduleTarget: 30, chapters: ["Papulosquamous Disorders", "Vesiculobullous Disorders", "Skin Infections", "Leprosy", "STIs", "Pigmentary Disorders"], topics: [:]),
        MedxDemoSubjectSpec(name: "Psychiatry", slug: "psychiatry", moduleTarget: 24, chapters: ["Schizophrenia", "Mood Disorders", "Anxiety Disorders", "Substance Use", "Psychopharmacology"], topics: [:]),
        MedxDemoSubjectSpec(name: "Anesthesia", slug: "anesthesia", moduleTarget: 24, chapters: ["Preoperative Assessment", "Inhalational Agents", "Intravenous Agents", "Muscle Relaxants", "Local Anaesthetics", "Airway"], topics: [:]),
        MedxDemoSubjectSpec(name: "Radiology", slug: "radiology", moduleTarget: 22, chapters: ["Physics & Basics", "Chest", "Neuroradiology", "GI & Abdomen", "Nuclear Medicine", "Radiotherapy"], topics: [:]),
        MedxDemoSubjectSpec(name: "Image-Based Questions", slug: "image-based", moduleTarget: 70, chapters: ["Clinical Images", "Instruments", "Specimens", "X-rays & CT", "Slides"], topics: [:]),
        MedxDemoSubjectSpec(name: "FMGE PYQs", slug: "fmge-pyqs", moduleTarget: 120, chapters: ["June 2026", "December 2025", "June 2025", "December 2024", "June 2024", "December 2023"], topics: [:]),
        MedxDemoSubjectSpec(name: "Recent Updates", slug: "recent-updates", moduleTarget: 53, chapters: ["National Programmes", "Guidelines 2026", "New Drugs", "Recent Classifications"], topics: [:])
    ]

    /// Marrow's module counts per subject, the same first twenty names. Sums to 960.
    static let marrowTargets: [Int] = [70, 54, 40, 68, 66, 52, 30, 72, 36, 38, 100, 96, 50, 32, 48, 30, 26, 20, 18, 14]

    /// The subject a question pool is chosen by, for the three pseudo-subjects.
    static func poolSubject(_ name: String) -> String {
        switch name {
        case "Image-Based Questions", "FMGE PYQs", "Recent Updates": return "Mixed"
        default: return name
        }
    }

    /// Module titles for one subject, chapter by chapter, `target` in all.
    static func layout(_ spec: MedxDemoSubjectSpec, target: Int) -> [(chapter: String, modules: [String])] {
        if !spec.topics.isEmpty {
            return spec.chapters.map { chapter in (chapter: chapter, modules: spec.topics[chapter] ?? [chapter]) }
        }
        let chapterCount = max(spec.chapters.count, 1)
        var out: [(chapter: String, modules: [String])] = []
        for (index, chapter) in spec.chapters.enumerated() {
            let base = target / chapterCount
            let extra = index < (target % chapterCount) ? 1 : 0
            let count = max(base + extra, 1)
            let names = (1...count).map { "\(chapter) · Part \($0)" }
            out.append((chapter: chapter, modules: names))
        }
        return out
    }
}

struct MedxDemoClassSpec: Sendable {
    let id: String
    let name: String
    let faculty: String
    let titles: [String]
}

// MARK: - Fixtures

/// Builds the whole account once, relative to the moment the app launched.
final class MedxDemoFixtures {
    static let documentPrefix = "projects/\(FirebaseConfig.projectId)/databases/(default)/documents/"

    let now: Date
    let uid: String
    let otherUid: String
    private let calendar = Calendar.current

    private(set) var modulesById: [String: MedxDemoModule] = [:]
    private(set) var ariseModules: [MedxDemoModule] = []
    private(set) var marrowModules: [MedxDemoModule] = []
    private(set) var papers: [(id: String, title: String, type: String, questions: Int, minutes: Int, startAt: Date)] = []
    private(set) var batchTests: [(id: String, name: String, subject: String, questions: Int, gradable: Bool)] = []

    /// Everything the store starts with, keyed `collection/docId`.
    private(set) var documents: [String: [String: Any]] = [:]

    init(now: Date = Date()) {
        self.now = now
        self.uid = MedxDemoMode.profile.uid
        self.otherUid = Profile.graveyard.uid
        buildCatalog()
        buildSeries()
        buildBatchTests()
        buildVideos()
        buildVod()
        buildFlashcards()
        buildActivity()
        buildCustomModules()
        buildTracker()
    }

    // MARK: Document shape

    static func document(path: String, fields: [String: MedxDemoValue], at date: Date) -> [String: Any] {
        let stamp = MedxDemoClock.timestamp(date)
        return [
            "name": documentPrefix + path,
            "fields": MedxDemoValue.fields(fields),
            "createTime": stamp,
            "updateTime": stamp
        ]
    }

    private func put(_ path: String, _ fields: [String: MedxDemoValue]) {
        documents[path] = MedxDemoFixtures.document(path: path, fields: fields, at: now)
    }

    private func daysAgo(_ days: Int, hour: Int, minute: Int = 0) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -days, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: Banks

    private func buildCatalog() {
        // ARISE: `qb_<n>` modules, one document per subject.
        var nextModule = 101
        var nextChapter = 1
        for (index, spec) in MedxDemoCatalog.ariseSubjects.enumerated() {
            let subjectId = index + 1
            var chapterValues: [MedxDemoValue] = []
            var subjectModules = 0
            var subjectQuestions = 0
            for entry in MedxDemoCatalog.layout(spec, target: spec.moduleTarget) {
                let chapterId = nextChapter
                nextChapter += 1
                var moduleValues: [MedxDemoValue] = []
                for name in entry.modules {
                    let id = "qb_\(nextModule)"
                    nextModule += 1
                    let featured = name == MedxDemoCatalog.featuredModuleName
                    let count = featured ? MedxDemoQuestions.microCocci.count : MedxDemoHash.int(id, in: 9...20)
                    let module = MedxDemoModule(
                        id: id, name: name, subject: spec.name, subjectId: subjectId,
                        chapter: entry.chapter, chapterId: chapterId, questionCount: count, featured: featured
                    )
                    modulesById[id] = module
                    ariseModules.append(module)
                    subjectModules += 1
                    subjectQuestions += count
                    let summary: [String: MedxDemoValue] = [
                        "id": .s(id),
                        "name": .s(name),
                        "questionCount": .i(count),
                        "chapter": .s(entry.chapter)
                    ]
                    moduleValues.append(.m(summary))
                }
                let chapter: [String: MedxDemoValue] = [
                    "id": .i(chapterId),
                    "name": .s(entry.chapter),
                    "modules": .a(moduleValues)
                ]
                chapterValues.append(.m(chapter))
            }
            put("medx_qbank_subjects/\(subjectId)", [
                "subjectId": .i(subjectId),
                "name": .s(spec.name),
                "slug": .s(spec.slug),
                "moduleCount": .i(subjectModules),
                "questionCount": .i(subjectQuestions),
                "chapters": .a(chapterValues)
            ])
        }

        // Marrow: one `medx_meta/qbank_fmge` document, `mw_` ids throughout.
        var marrowSubjects: [MedxDemoValue] = []
        var marrowChapterSeq = 5000
        for (index, target) in MedxDemoCatalog.marrowTargets.enumerated() {
            guard index < MedxDemoCatalog.ariseSubjects.count else { break }
            let base = MedxDemoCatalog.ariseSubjects[index]
            let spec = MedxDemoSubjectSpec(name: base.name, slug: base.slug, moduleTarget: target, chapters: base.chapters, topics: [:])
            let subjectKey = "mw_" + MedxDemoHash.hex("marrow-subject-\(base.slug)", length: 12)
            var chapterValues: [MedxDemoValue] = []
            var subjectModules = 0
            var subjectQuestions = 0
            for entry in MedxDemoCatalog.layout(spec, target: target) {
                marrowChapterSeq += 1
                let chapterKey = "mw_" + MedxDemoHash.hex("marrow-chapter-\(base.slug)-\(entry.chapter)", length: 12)
                var moduleValues: [MedxDemoValue] = []
                for name in entry.modules {
                    let id = "mw_" + MedxDemoHash.hex("marrow-module-\(base.slug)-\(name)", length: 24)
                    let count = MedxDemoHash.int(id, in: 10...20)
                    let module = MedxDemoModule(
                        id: id, name: name, subject: base.name, subjectId: index + 1,
                        chapter: entry.chapter, chapterId: marrowChapterSeq, questionCount: count, featured: false
                    )
                    modulesById[id] = module
                    marrowModules.append(module)
                    subjectModules += 1
                    subjectQuestions += count
                    let summary: [String: MedxDemoValue] = [
                        "id": .s(id),
                        "name": .s(name),
                        "questionCount": .i(count),
                        "chapter": .s(entry.chapter)
                    ]
                    moduleValues.append(.m(summary))
                }
                let chapter: [String: MedxDemoValue] = [
                    "id": .s(chapterKey),
                    "name": .s(entry.chapter),
                    "modules": .a(moduleValues)
                ]
                chapterValues.append(.m(chapter))
            }
            let subject: [String: MedxDemoValue] = [
                "id": .s(subjectKey),
                "bank": .s("marrow"),
                "name": .s(base.name),
                "slug": .s(base.slug),
                "moduleCount": .i(subjectModules),
                "questionCount": .i(subjectQuestions),
                "chapters": .a(chapterValues)
            ]
            marrowSubjects.append(.m(subject))
        }
        put("medx_meta/qbank_fmge", [
            "course": .s("fmge"),
            "name": .s("Marrow FMGE"),
            "subjects": .a(marrowSubjects)
        ])
    }

    /// First ARISE module in a subject (optionally a chapter), for attempts and custom modules.
    func modules(inSubject subject: String, chapter: String? = nil) -> [MedxDemoModule] {
        ariseModules.filter { $0.subject == subject && (chapter == nil || $0.chapter == chapter) }
    }

    var featuredModule: MedxDemoModule? {
        ariseModules.first { $0.featured }
    }

    /// The questions of one module, as `Question` maps, deterministic per id.
    func questions(forModule module: MedxDemoModule) -> [[String: MedxDemoValue]] {
        if module.featured {
            return MedxDemoQuestions.microCocci.enumerated().map { index, mcq in
                MedxDemoQuestions.question(mcq, id: 6_120_000 + index + 1, number: index + 1, reference: "Ananthanarayan & Paniker's Textbook of Microbiology, 11th ed.")
            }
        }
        let pool = MedxDemoQuestions.pool(for: MedxDemoCatalog.poolSubject(module.subject))
        let seed = Int(MedxDemoHash.value(module.id) % 997)
        let base = questionBase(for: module.id)
        return (0..<module.questionCount).map { index in
            let mcq = pool[(seed + index) % pool.count]
            return MedxDemoQuestions.question(mcq, id: base + index + 1, number: index + 1, reference: nil)
        }
    }

    private func questionBase(for key: String) -> Int {
        if key.hasPrefix("qb_"), let number = Int(key.dropFirst(3)) {
            return number * 1000
        }
        return Int(MedxDemoHash.value(key) % 900_000 + 100_000) * 1000
    }

    /// `medx_qbank_modules/<id>`, built on first read.
    func moduleDocument(id: String) -> [String: Any]? {
        guard let module = modulesById[id] else { return nil }
        let questionValues = self.questions(forModule: module).map { MedxDemoValue.m($0) }
        let fields: [String: MedxDemoValue] = [
            "moduleId": .s(module.id),
            "subjectId": .i(module.subjectId),
            "subject": .s(module.subject),
            "chapterId": .i(module.chapterId),
            "chapter": .s(module.chapter),
            "name": .s(module.name),
            "description": .s("\(module.subject) · \(module.chapter)"),
            "questionCount": .i(module.questionCount),
            "questions": .a(questionValues)
        ]
        return MedxDemoFixtures.document(path: "medx_qbank_modules/\(id)", fields: fields, at: now)
    }

    // MARK: Series and batch papers

    private func buildSeries() {
        var list: [(id: String, title: String, type: String, questions: Int, minutes: Int, startAt: Date)] = []
        for number in 1...6 {
            let start = daysAgo((6 - number) * 16 + 3, hour: 10)
            list.append((id: MedxDemoHash.hex("gt-\(number)", length: 24), title: "Grand Test \(String(format: "%02d", number))", type: "grand", questions: 150, minutes: 150, startAt: start))
        }
        list.append((id: MedxDemoHash.hex("mock-300", length: 24), title: "FMGE Full Mock · 300", type: "grand", questions: 300, minutes: 300, startAt: daysAgo(9, hour: 9)))
        let minis = ["Mixed Bag", "Pre-clinical Sprint", "Para-clinical Sprint", "Clinical Sprint", "Image Based", "One-liners", "PYQ Recall", "High Yield Rapid", "Short Subjects", "Last-week Revision"]
        for (index, name) in minis.enumerated() {
            list.append((id: MedxDemoHash.hex("mini-\(index)", length: 24), title: "Mini Test \(String(format: "%02d", index + 1)) · \(name)", type: "mini", questions: 50, minutes: 50, startAt: daysAgo(index * 11 + 2, hour: 18)))
        }
        for (index, spec) in MedxDemoCatalog.ariseSubjects.prefix(20).enumerated() {
            list.append((id: MedxDemoHash.hex("st-\(spec.slug)", length: 24), title: "\(spec.name) · Subject Test", type: "subject", questions: 40, minutes: 40, startAt: daysAgo(index * 6 + 5, hour: 20)))
        }
        papers = list

        var tests: [MedxDemoValue] = []
        var totalQuestions = 0
        for (index, paper) in list.enumerated() {
            totalQuestions += paper.questions
            let entry: [String: MedxDemoValue] = [
                "id": .s(paper.id),
                "title": .s(paper.title),
                "type": .s(paper.type),
                "year": .s(String(calendar.component(.year, from: paper.startAt))),
                "questions": .i(paper.questions),
                "durationMin": .i(paper.minutes),
                "startAt": .d((paper.startAt.timeIntervalSince1970 * 1000).rounded()),
                "isPaid": .b(index % 4 == 0),
                "hasQuestions": .b(true)
            ]
            tests.append(.m(entry))
        }
        put("medx_meta/series_fmge", [
            "course": .s("fmge"),
            "name": .s("Marrow FMGE Test Series"),
            "counts": .m(["papers": .i(list.count), "questions": .i(totalQuestions)]),
            "tests": .a(tests)
        ])
    }

    private func buildBatchTests() {
        batchTests = [
            (id: "test_1", name: "ARISE Grand Test 1", subject: "All subjects", questions: 200, gradable: true),
            (id: "test_2", name: "ARISE Grand Test 2", subject: "All subjects", questions: 200, gradable: true),
            (id: "test_3", name: "Para-clinical Practice Paper", subject: "Pathology · Pharmacology · Microbiology", questions: 100, gradable: false),
            (id: "test_4", name: "Clinical Practice Paper", subject: "Medicine · Surgery · OBG · Pediatrics", questions: 100, gradable: false),
            // Shaped like a fresh upload: its questions carry no ids at all (see paperQuestions).
            (id: "test_5", name: "ARISE Mock 7 (new upload)", subject: "All subjects", questions: 20, gradable: true)
        ]
        for test in batchTests {
            var fields: [String: MedxDemoValue] = [
                "testId": .s(test.id),
                "batchId": .s("arise_dec26"),
                "batch": .s("ARISE Online · Dec 26"),
                "name": .s(test.name),
                "subject": .s(test.subject),
                "mode": .s(test.gradable ? "exam" : "practice"),
                "testType": .s(test.gradable ? "grand" : "practice"),
                "questionCount": .i(test.questions),
                "officialTimeMins": .i(test.questions),
                "gradable": .b(test.gradable)
            ]
            if test.gradable {
                fields["gradedCount"] = .i(test.questions)
            }
            if test.id == "test_1" {
                fields["priorAttempt"] = .m([
                    "status": .s("completed"),
                    "correct": .i(131),
                    "questionCount": .i(200),
                    "testRank": .i(412)
                ])
            }
            put("medx_tests/\(test.id)", fields)
        }
    }

    /// The questions of a series paper or batch paper, generated from the mixed pools.
    func paperQuestions(testId: String) -> [[String: MedxDemoValue]]? {
        let count: Int
        if let paper = papers.first(where: { $0.id == testId }) {
            count = paper.questions
        } else if let test = batchTests.first(where: { $0.id == testId }) {
            count = test.questions
        } else {
            return nil
        }
        let pool = MedxDemoQuestions.microCocci + MedxDemoQuestions.pathology + MedxDemoQuestions.pharmacology + MedxDemoQuestions.general
        let seed = Int(MedxDemoHash.value(testId) % 991)
        let base = questionBase(for: "paper-\(testId)")
        return (0..<count).map { index in
            var question = MedxDemoQuestions.question(pool[(seed + index * 7) % pool.count], id: base + index + 1, number: index + 1, reference: nil)
            // The newest uploads arrive without question ids; the app has to tell them apart anyway.
            if testId == "test_5" {
                question["id"] = nil
            }
            return question
        }
    }

    /// `medx_test_questions` parts for one paper, 100 questions to a part.
    func testQuestionParts(testId: String) -> [(path: String, document: [String: Any])] {
        guard let all = paperQuestions(testId: testId) else { return [] }
        var out: [(path: String, document: [String: Any])] = []
        var part = 0
        var start = 0
        while start < all.count {
            let end = min(start + 100, all.count)
            let slice = all[start..<end].map { MedxDemoValue.m($0) }
            let path = "medx_test_questions/\(testId)__\(part)"
            let fields: [String: MedxDemoValue] = [
                "testId": .s(testId),
                "part": .i(part),
                "questions": .a(slice)
            ]
            out.append((path: path, document: MedxDemoFixtures.document(path: path, fields: fields, at: now)))
            part += 1
            start = end
        }
        return out
    }

    // MARK: Classes and the VOD bucket

    static let streamA = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    static let streamB = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"

    private(set) var videos: [[String: MedxDemoValue]] = []

    private func buildVideos() {
        let december: [MedxDemoClassSpec] = [
            MedxDemoClassSpec(id: "6", name: "Microbiology", faculty: "Dr. Meera Krishnan", titles: ["General Microbiology & Sterilisation", "Immunology I: Antigens & Antibodies", "Gram-Positive Cocci", "Enterobacteriaceae & Vibrio", "Virology: Herpes & Hepatitis"]),
            MedxDemoClassSpec(id: "4", name: "Pathology", faculty: "Dr. Arvind Rao", titles: ["Cell Injury & Inflammation", "Neoplasia", "Anemias", "Leukemias & Lymphomas"]),
            MedxDemoClassSpec(id: "5", name: "Pharmacology", faculty: "Dr. Kavya Iyer", titles: ["General Pharmacology", "ANS Drugs", "Antimicrobials"]),
            MedxDemoClassSpec(id: "11", name: "Medicine", faculty: "Dr. Sanjay Menon", titles: ["Cardiology Essentials", "Endocrinology", "Neurology High Yield"]),
            MedxDemoClassSpec(id: "8", name: "Community Medicine", faculty: "Dr. Farah Siddiqui", titles: ["Epidemiology", "Biostatistics", "National Health Programmes"])
        ]
        let june: [MedxDemoClassSpec] = [
            MedxDemoClassSpec(id: "1", name: "Anatomy", faculty: "Dr. Rohit Nair", titles: ["Upper Limb in One Shot", "Head & Neck Rapid Revision"]),
            MedxDemoClassSpec(id: "2", name: "Physiology", faculty: "Dr. Lakshmi Prasad", titles: ["CVS & Respiratory Physiology", "Renal & Endocrine Physiology"]),
            MedxDemoClassSpec(id: "13", name: "Obstetrics", faculty: "Dr. Ananya Bose", titles: ["Labour & Obstetric Haemorrhage", "Medical Disorders in Pregnancy"]),
            MedxDemoClassSpec(id: "12", name: "Surgery", faculty: "Dr. Vikram Shetty", titles: ["Hepatobiliary Surgery", "Trauma & Burns"])
        ]
        let batches: [(id: String, name: String, subjects: [MedxDemoClassSpec])] = [
            (id: "arise_dec26", name: "ARISE Online · Dec 26", subjects: december),
            (id: "arise_rr_jun26", name: "ARISE Rapid Revision · Jun 26", subjects: june)
        ]
        var serial = 1
        for batch in batches {
            for subject in batch.subjects {
                for (index, title) in subject.titles.enumerated() {
                    let id = "arise_\(1000 + serial)"
                    let seconds = MedxDemoHash.int(id, in: 4_200...9_600)
                    let fields: [String: MedxDemoValue] = [
                        "id": .s(id),
                        "source": .s("ARISE"),
                        "batchId": .s(batch.id),
                        "batch": .s(batch.name),
                        "subjectId": .s(subject.id),
                        "subject": .s(subject.name),
                        "title": .s("\(subject.name) Class \(index + 1) · \(title)"),
                        "faculty": .s(subject.faculty),
                        "durationSeconds": .i(seconds),
                        "duration": .s(String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)),
                        "streamUrl": .s(serial % 2 == 0 ? MedxDemoFixtures.streamB : MedxDemoFixtures.streamA),
                        "kind": .s("hls")
                    ]
                    put("medx_videos/\(id)", fields)
                    videos.append(fields)
                    serial += 1
                }
            }
        }

        put("medx_video_folders/fmge_dec26_imports", [
            "name": .s("FMGE Dec 26 · Imports"),
            "order": .i(1),
            "subjects": .a([
                .m(["id": .s("vod-micro"), "name": .s("Microbiology"), "order": .i(1), "sticker": .s("cross.case.fill")]),
                .m(["id": .s("vod-patho"), "name": .s("Pathology"), "order": .i(2), "sticker": .s("pills.fill")])
            ])
        ])
    }

    private func buildVod() {
        let named: [(key: String, subject: String, faculty: String)] = [
            ("MicrobiologyOct08_Virology.m3u8", "Microbiology", "Dr. Meera Krishnan"),
            ("PathologyOct07_Neoplasia_Part2.m3u8", "Pathology", "Dr. Arvind Rao"),
            ("PharmaOct06_Antimicrobials.m3u8", "Pharmacology", "Dr. Kavya Iyer"),
            ("MedicineOct05_Endocrine.m3u8", "Medicine", "Dr. Sanjay Menon"),
            ("PSMOct04_Biostatistics.m3u8", "Community Medicine", "Dr. Farah Siddiqui"),
            ("OBGOct03_PPH.m3u8", "Obstetrics", "Dr. Ananya Bose"),
            ("SurgeryOct02_Thyroid.m3u8", "Surgery", "Dr. Vikram Shetty"),
            ("ENTOct01_Larynx.m3u8", "ENT", "Dr. Nikhil Varma"),
            ("OphthalSep30_Glaucoma.m3u8", "Ophthalmology", "Dr. Divya Raman"),
            ("PediatricsSep29_Neonatology.m3u8", "Pediatrics", "Dr. Pooja Kulkarni")
        ]
        var newest: Date?
        for index in 0..<36 {
            let uploaded = now.addingTimeInterval(-Double(index) * 15.5 * 3600 - 2_400)
            if newest == nil { newest = uploaded }
            let id = "vod_\(String(format: "%03d", 36 - index))"
            let pick = named[index % named.count]
            let opaque = index % 3 == 2
            let key = opaque ? "rec" + MedxDemoHash.hex("vod-\(index)", length: 20) : pick.key
            let folder = opaque ? (index % 2 == 0 ? "7f2a11" : "standalone-\(index)") : "dec26-\(pick.subject.lowercased().replacingOccurrences(of: " ", with: "-"))"
            let seconds = MedxDemoHash.int(id, in: 3_000...8_400)
            put("medx_vod/\(id)", [
                "id": .s(id),
                "fileKey": .s(key),
                "title": .s(key),
                "folder": .s(folder),
                "streamUrl": .s(index % 2 == 0 ? MedxDemoFixtures.streamA : MedxDemoFixtures.streamB),
                "thumbnailUrl": .s(""),
                "subtitlesUrl": .s(""),
                "hasSubtitles": .b(false),
                "subject": .s(opaque ? "" : pick.subject),
                "faculty": .s(opaque ? "" : pick.faculty),
                "batch": .s("Dec 26"),
                "durationSeconds": .i(seconds),
                "durationPreciseSeconds": .i(seconds - 37),
                "uploadedAt": .t(uploaded)
            ])
        }
        put("medx_vod/_meta", [
            "count": .i(36),
            "lastUploadedAt": .t(newest ?? now),
            "updatedAt": .t(now)
        ])
    }

    // MARK: Flashcards

    private func buildFlashcards() {
        let decks: [(id: Int, name: String, chapters: [String])] = [
            (1, "Anatomy", ["Brachial Plexus", "Cranial Nerves", "Embryology Timelines"]),
            (2, "Biochemistry", ["Vitamins", "Enzyme Deficiencies", "Lipid Metabolism"]),
            (4, "Pathology", ["Tumour Markers", "Stains", "Translocations"]),
            (5, "Pharmacology", ["Antidotes", "Drugs of Choice", "Adverse Effects"]),
            (6, "Microbiology", ["Culture Media", "Toxins", "Vectors"]),
            (8, "Community Medicine", ["Vaccines", "Programmes", "Indicators"]),
            (10, "Ophthalmology", ["Signs", "Instruments"]),
            (11, "Medicine", ["Eponymous Signs", "Investigations of Choice", "Scores"])
        ]
        for deck in decks {
            var cards: [MedxDemoValue] = []
            var cardId = deck.id * 1000
            for chapter in deck.chapters {
                for number in 1...MedxDemoHash.int("\(deck.name)-\(chapter)", in: 8...16) {
                    cardId += 1
                    cards.append(.m([
                        "id": .i(cardId),
                        "name": .s("\(chapter) \(number)"),
                        "description": .s("\(deck.name) · \(chapter)"),
                        "chapter": .s(chapter)
                    ]))
                }
            }
            put("medx_flashcard_subjects/\(deck.id)", [
                "subjectId": .i(deck.id),
                "name": .s(deck.name),
                "slug": .s(deck.name.lowercased().replacingOccurrences(of: " ", with: "-")),
                "cardCount": .i(cards.count),
                "cards": .a(cards)
            ])
        }
    }

    // MARK: Attempts, bookmarks, watch history

    private func responses(for questions: [[String: MedxDemoValue]], attempted: Int, score: Int, seed: String) -> [MedxDemoValue] {
        // Which of the attempted questions were right: a deterministic shuffle, not front-loaded.
        let order = (0..<max(attempted, 0)).sorted {
            MedxDemoHash.value("\(seed)-\($0)") < MedxDemoHash.value("\(seed)-\($1)")
        }
        let rightSlots = Set(order.prefix(max(min(score, attempted), 0)))
        var out: [MedxDemoValue] = []
        for (index, question) in questions.enumerated() {
            guard case .i(let qid)? = question["id"], case .a(let correctIds)? = question["correctIds"],
                  case .i(let right)? = correctIds.first else { continue }
            if index >= attempted {
                out.append(.m(["questionId": .i(qid), "correct": .b(false)]))
                continue
            }
            let isRight = rightSlots.contains(index)
            let wrong = qid * 10 + ((right - qid * 10) % 4) + 1
            out.append(.m([
                "questionId": .i(qid),
                "chosenId": .i(isRight ? right : wrong),
                "correct": .b(isRight)
            ]))
        }
        return out
    }

    private func addAttempt(
        id: String,
        kind: String,
        sourceId: String,
        name: String,
        subject: String,
        questions: [[String: MedxDemoValue]],
        accuracy: Double,
        finished: Date,
        mode: String = "exam",
        sections: [MedxDemoValue]? = nil
    ) {
        let total = questions.count
        let attempted = total > 30 ? total - Int(Double(total) * 0.04) : total
        let score = Int((Double(attempted) * accuracy).rounded())
        var fields: [String: MedxDemoValue] = [
            "uid": .s(uid),
            "profile": .s(MedxDemoMode.profile.handle),
            "kind": .s(kind),
            "sourceId": .s(sourceId),
            "name": .s(name),
            "subject": .s(subject),
            "mode": .s(mode),
            "gradable": .b(true),
            "total": .i(total),
            "score": .i(score),
            "attempted": .i(attempted),
            "durationSeconds": .i(attempted * MedxDemoHash.int(id, in: 38...62)),
            "finishedAt": .s(MedxDemoClock.iso(finished)),
            "responses": .a(responses(for: questions, attempted: attempted, score: score, seed: id))
        ]
        if let sections {
            fields["sections"] = .a(sections)
        }
        put("medx_attempts/\(id)", fields)
    }

    private func buildActivity() {
        let micro = modules(inSubject: "Microbiology")
        let patho = modules(inSubject: "Pathology")
        let pharma = modules(inSubject: "Pharmacology")
        let featured = featuredModule ?? micro[0]

        // (days ago, hour, minute, module, accuracy). Today is relative to launch: minutes before now.
        var plan: [(days: Int, hour: Int, minute: Int, module: MedxDemoModule, accuracy: Double)] = []
        func add(_ days: Int, _ hour: Int, _ minute: Int, _ module: MedxDemoModule?, _ accuracy: Double) {
            guard let module else { return }
            plan.append((days: days, hour: hour, minute: minute, module: module, accuracy: accuracy))
        }
        add(1, 9, 40, micro.first { $0.name == "Bacterial Genetics" }, 0.62)
        add(1, 21, 10, micro.first { $0.name == "Hypersensitivity" }, 0.71)
        add(2, 10, 5, micro.first { $0.name == "Sterilisation & Disinfection" }, 0.80)
        add(2, 16, 30, featured, 0.58)
        add(2, 22, 15, pharma.first, 0.66)
        add(3, 20, 0, micro.first { $0.name == "Culture Media & Methods" }, 0.69)
        add(4, 11, 20, patho.first { $0.name == "Leukemias" }, 0.64)
        add(4, 19, 45, patho.first { $0.name == "Lymphomas" }, 0.73)
        add(5, 9, 0, patho.first { $0.name == "Hemolytic Anemias" }, 0.57)
        add(6, 18, 30, patho.first { $0.name == "Neoplasia I" }, 0.75)
        add(8, 10, 10, patho.first { $0.name == "Acute & Chronic Inflammation" }, 0.78)
        add(8, 21, 0, pharma.dropFirst().first, 0.61)
        add(9, 17, 40, modules(inSubject: "Biochemistry").first, 0.55)
        add(10, 9, 30, patho.first { $0.name == "Cell Injury & Adaptation" }, 0.79)
        add(10, 20, 20, modules(inSubject: "Physiology").first, 0.68)
        add(11, 11, 0, modules(inSubject: "Anatomy").first, 0.6)
        add(11, 22, 5, modules(inSubject: "Anatomy").dropFirst(9).first, 0.65)
        add(12, 19, 0, modules(inSubject: "Forensic Medicine").first, 0.7)
        add(13, 10, 30, modules(inSubject: "Community Medicine").first, 0.63)
        add(13, 21, 45, pharma.dropFirst(2).first, 0.59)

        for (index, entry) in plan.enumerated() {
            addAttempt(
                id: "demo_attempt_\(String(format: "%02d", index + 1))",
                kind: "qbank",
                sourceId: entry.module.id,
                name: entry.module.name,
                subject: entry.module.subject,
                questions: questions(forModule: entry.module),
                accuracy: entry.accuracy,
                finished: daysAgo(entry.days, hour: entry.hour, minute: entry.minute)
            )
        }

        // Today: two sittings already, so the goal ring is part-way round and the streak is live.
        addAttempt(
            id: "demo_attempt_today_1", kind: "qbank", sourceId: featured.id, name: featured.name,
            subject: featured.subject, questions: questions(forModule: featured), accuracy: 0.75,
            finished: now.addingTimeInterval(-3 * 3600)
        )
        if let next = micro.first(where: { $0.name == "Pneumococcus & Enterococcus" }) {
            addAttempt(
                id: "demo_attempt_today_2", kind: "qbank", sourceId: next.id, name: next.name,
                subject: next.subject, questions: questions(forModule: next), accuracy: 0.69,
                finished: now.addingTimeInterval(-40 * 60), mode: "revision"
            )
        }

        // A sectioned Grand Test, a batch paper and a series mini test.
        if let gt = papers.first(where: { $0.title == "Grand Test 05" }), let all = paperQuestions(testId: gt.id) {
            var sections: [MedxDemoValue] = []
            let scores = [33, 29, 31]
            for block in 0..<3 {
                sections.append(.m([
                    "index": .i(block),
                    "label": .s("Section \(block + 1)"),
                    "total": .i(50),
                    "score": .i(scores[block]),
                    "attempted": .i(48),
                    "seconds": .i(2_760 + block * 95)
                ]))
            }
            addAttempt(
                id: "demo_attempt_gt05", kind: "series", sourceId: gt.id, name: gt.title, subject: gt.title,
                questions: all, accuracy: 0.6458, finished: daysAgo(3, hour: 13, minute: 30), sections: sections
            )
        }
        if let all = paperQuestions(testId: "test_1") {
            addAttempt(
                id: "demo_attempt_test1", kind: "test", sourceId: "test_1", name: "ARISE Grand Test 1",
                subject: "All subjects", questions: all, accuracy: 0.655, finished: daysAgo(7, hour: 12)
            )
        }
        if let mini = papers.first(where: { $0.type == "mini" }), let all = paperQuestions(testId: mini.id) {
            addAttempt(
                id: "demo_attempt_mini01", kind: "series", sourceId: mini.id, name: mini.title, subject: mini.title,
                questions: all, accuracy: 0.72, finished: daysAgo(5, hour: 21, minute: 30)
            )
        }

        // Bookmarks: questions from the featured module and the other two pools.
        let featuredQuestions = questions(forModule: featured)
        var bookmarkSources: [(module: MedxDemoModule, question: [String: MedxDemoValue], daysAgo: Int)] = []
        if featuredQuestions.count > 8 {
            bookmarkSources.append((module: featured, question: featuredQuestions[8], daysAgo: 0))
            bookmarkSources.append((module: featured, question: featuredQuestions[2], daysAgo: 2))
        }
        if let leuk = patho.first(where: { $0.name == "Lymphomas" }), let q = questions(forModule: leuk).first {
            bookmarkSources.append((module: leuk, question: q, daysAgo: 4))
        }
        if let ph = pharma.first, let q = questions(forModule: ph).dropFirst().first {
            bookmarkSources.append((module: ph, question: q, daysAgo: 6))
        }
        for source in bookmarkSources {
            guard case .i(let qid)? = source.question["id"] else { continue }
            let docId = "\(uid)_\(source.module.id)_\(qid)"
            put("medx_bookmarks/\(docId)", [
                "sourceId": .s(source.module.id),
                "ownerId": .s(uid),
                "sourceName": .s(source.module.name),
                "subject": .s(source.module.subject),
                "question": .m(source.question),
                "bookmarkedAt": .s(MedxDemoClock.iso(daysAgo(source.daysAgo, hour: 8, minute: 15)))
            ])
        }

        // Watch history: two half-watched classes and one finished.
        let history: [(index: Int, fraction: Double, hoursAgo: Double)] = [(2, 0.46, 5), (5, 0.63, 27), (0, 0.97, 52)]
        for entry in history where entry.index < videos.count {
            let video = videos[entry.index]
            guard case .s(let videoId)? = video["id"], case .i(let seconds)? = video["durationSeconds"] else { continue }
            put("medx_watch_history/\(uid)_\(videoId)", [
                "video": .m(video),
                "ownerId": .s(uid),
                "positionSeconds": .d((Double(seconds) * entry.fraction).rounded()),
                "durationSeconds": .d(Double(seconds)),
                "watchedAt": .s(MedxDemoClock.iso(now.addingTimeInterval(-entry.hoursAgo * 3600)))
            ])
        }
    }

    // MARK: Custom modules

    private func source(_ module: MedxDemoModule) -> MedxDemoValue {
        .m([
            "type": .s("module"),
            "moduleId": .s(module.id),
            "name": .s(module.name),
            "chapter": .s(module.chapter),
            "subject": .s(module.subject),
            "bank": .s(module.id.hasPrefix("mw_") ? "marrow" : "arise"),
            "questionCount": .i(module.questionCount)
        ])
    }

    private func buildCustomModules() {
        let bacteriology = modules(inSubject: "Microbiology", chapter: "Systemic Bacteriology")
        let mixed = Array(modules(inSubject: "Pathology", chapter: "Hematology").prefix(3)) + Array(modules(inSubject: "Pharmacology").prefix(2))
        let pyqs = Array(modules(inSubject: "FMGE PYQs").prefix(4))
        let marrowMicro = Array(marrowModules.filter { $0.subject == "Microbiology" }.prefix(2))

        let rows: [(id: String, owner: String, name: String, note: String, sources: [MedxDemoModule], limit: Int, daysAgo: Int)] = [
            (id: "mgk4q1x7a3f2", owner: uid, name: "Bacteriology sprint", note: "Cocci to spirochetes before GT 07", sources: Array(bacteriology.prefix(5)) + marrowMicro, limit: 40, daysAgo: 1),
            (id: "mgf0z9c2b81d", owner: otherUid, name: "Heme + Pharma mix", note: "Mathu's Sunday paper", sources: mixed, limit: 0, daysAgo: 3),
            (id: "mg9w2e6t0c4a", owner: uid, name: "PYQ recall · last 4 papers", note: "", sources: pyqs, limit: 60, daysAgo: 6)
        ]
        for row in rows where !row.sources.isEmpty {
            let stamp = MedxDemoClock.iso(daysAgo(row.daysAgo, hour: 19, minute: 20))
            put("medx_custom_modules/\(row.id)", [
                "id": .s(row.id),
                "uid": .s(row.owner),
                "name": .s(row.name),
                "note": .s(row.note),
                "sources": .a(row.sources.map { source($0) }),
                "shuffle": .b(true),
                "limit": .i(row.limit),
                "createdAt": .s(stamp),
                "updatedAt": .s(stamp)
            ])
        }
    }

    // MARK: Syllabus tracker

    private func buildTracker() {
        // Stage pattern per subject: Videos, R1, R2, PYQs, RevisionVideos, Qbank.
        let rows: [(String, [Bool])] = [
            ("Anatomy", [true, true, true, true, false, true]),
            ("Physiology", [true, true, true, true, true, true]),
            ("Biochemistry", [true, true, false, true, false, true]),
            ("Pathology", [true, true, false, true, false, true]),
            ("Pharmacology", [true, true, false, false, false, true]),
            ("Microbiology", [true, false, false, false, false, true]),
            ("Forensic Medicine", [true, true, false, true, false, false]),
            ("Community Medicine", [true, false, false, true, false, false]),
            ("ENT", [true, false, false, false, false, false]),
            ("Ophthalmology", [true, false, false, false, false, false]),
            ("Medicine", [true, false, false, false, false, false]),
            ("Surgery", [true, false, false, false, false, false]),
            ("Obstetrics", [true, true, false, false, false, false]),
            ("Gynaecology", [false, false, false, false, false, false]),
            ("Pediatrics", [true, false, false, false, false, false]),
            ("Orthopedics", [false, false, false, false, false, false]),
            ("Dermatology", [true, false, false, false, false, false]),
            ("Psychiatry", [true, true, false, false, false, false]),
            ("Anesthesia", [false, false, false, false, false, false]),
            ("Radiology", [false, false, false, false, false, false])
        ]
        let keys = ["Videos", "R1", "R2", "PYQs", "RevisionVideos", "Qbank"]
        var subjects: [String: MedxDemoValue] = [:]
        for (name, stages) in rows {
            var cell: [String: MedxDemoValue] = [:]
            for (index, key) in keys.enumerated() where index < stages.count {
                cell[key] = .b(stages[index])
            }
            subjects[name] = .m(cell)
        }
        put("user_tracker/\(uid)", ["subjects": .m(subjects)])
    }
}

// MARK: - The backend

/// The in-memory Firestore. One lock around everything: requests are small and the store is
/// touched only from `URLProtocol` threads.
final class MedxDemoBackend: @unchecked Sendable {
    static let shared = MedxDemoBackend()

    struct Answer {
        let status: Int
        let body: Data
    }

    struct Filter {
        let path: [String]
        let op: String
        let value: [String: Any]
    }

    private let lock = NSLock()
    private var fixtures: MedxDemoFixtures?
    private var store: [String: [String: Any]] = [:]

    private init() {}

    func respond(to request: URLRequest) -> Answer {
        lock.lock()
        defer { lock.unlock() }

        if fixtures == nil {
            let built = MedxDemoFixtures()
            fixtures = built
            store = built.documents
            print("[MedxDemo] fixtures ready: \(store.count) documents")
        }

        guard let url = request.url else { return json(400, [:]) }
        let host = url.host?.lowercased() ?? ""
        let method = (request.httpMethod ?? "GET").uppercased()
        let body = Self.jsonBody(of: request)

        switch host {
        case "identitytoolkit.googleapis.com":
            return identity(url: url, body: body)
        case "securetoken.googleapis.com":
            return token()
        default:
            return firestore(url: url, method: method, body: body)
        }
    }

    // MARK: Auth

    private func identity(url: URL, body: [String: Any]?) -> Answer {
        let email = ((body?["email"] as? String) ?? MedxDemoMode.profile.email).lowercased()
        let profile = Profile.allProfiles.first { $0.email.lowercased() == email } ?? MedxDemoMode.profile
        if url.path.hasSuffix(":lookup") {
            let user: [String: Any] = ["localId": profile.uid, "email": profile.email, "displayName": profile.displayName]
            return json(200, ["users": [user]])
        }
        return json(200, [
            "kind": "identitytoolkit#VerifyPasswordResponse",
            "localId": profile.uid,
            "email": profile.email,
            "displayName": profile.displayName,
            "idToken": MedxDemoMode.idToken,
            "registered": true,
            "refreshToken": MedxDemoMode.refreshToken,
            "expiresIn": "31536000"
        ])
    }

    private func token() -> Answer {
        json(200, [
            "access_token": MedxDemoMode.idToken,
            "expires_in": "31536000",
            "token_type": "Bearer",
            "refresh_token": MedxDemoMode.refreshToken,
            "id_token": MedxDemoMode.idToken,
            "user_id": MedxDemoMode.profile.uid,
            "project_id": FirebaseConfig.projectId
        ])
    }

    // MARK: Firestore routing

    private func firestore(url: URL, method: String, body: [String: Any]?) -> Answer {
        let path = url.path
        guard let marker = path.range(of: "/documents") else { return json(200, [:]) }
        var rest = String(path[marker.upperBound...])
        var action: String?
        if rest.hasPrefix(":") {
            action = String(rest.dropFirst())
            rest = ""
        } else {
            if rest.hasPrefix("/") { rest.removeFirst() }
            if let colon = rest.lastIndex(of: ":") {
                action = String(rest[rest.index(after: colon)...])
                rest = String(rest[..<colon])
            }
        }

        if let action {
            switch action {
            case "runQuery":
                return runQuery(parent: rest, body: body)
            case "batchGet":
                return batchGet(body: body)
            case "commit":
                return commit(body: body)
            case "beginTransaction":
                return json(200, ["transaction": "bWVkeC1kZW1v"])
            default:
                return json(200, [:])
            }
        }

        let segments = rest.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return json(200, [:]) }
        let isDocument = segments.count % 2 == 0
        let key = segments.joined(separator: "/")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let mask = queryItems.filter { $0.name == "updateMask.fieldPaths" }.compactMap { $0.value }

        switch method {
        case "GET":
            return isDocument ? getDocument(key) : listCollection(key)
        case "PATCH":
            guard isDocument else { return json(200, [:]) }
            return writeDocument(key, fields: Self.incomingFields(body), mask: mask.isEmpty ? nil : mask)
        case "POST":
            if isDocument {
                return writeDocument(key, fields: Self.incomingFields(body), mask: nil)
            }
            let docId = queryItems.first { $0.name == "documentId" }?.value ?? Self.newId()
            return writeDocument(key + "/" + docId, fields: Self.incomingFields(body), mask: nil)
        case "DELETE":
            store.removeValue(forKey: key)
            return json(200, [:])
        default:
            return json(200, [:])
        }
    }

    // MARK: Reads

    private func getDocument(_ key: String) -> Answer {
        if let document = store[key] {
            return json(200, document)
        }
        let modulePrefix = "medx_qbank_modules/"
        if key.hasPrefix(modulePrefix), let fixtures,
           let document = fixtures.moduleDocument(id: String(key.dropFirst(modulePrefix.count))) {
            store[key] = document
            return json(200, document)
        }
        let error: [String: Any] = [
            "code": 404,
            "message": "Document \"\(MedxDemoFixtures.documentPrefix)\(key)\" not found.",
            "status": "NOT_FOUND"
        ]
        return json(404, ["error": error])
    }

    private func listCollection(_ collection: String) -> Answer {
        let listed = documentsIn(collection).sorted { Self.name(of: $0) < Self.name(of: $1) }
        if listed.isEmpty { return json(200, [:]) }
        return json(200, ["documents": listed])
    }

    private func documentsIn(_ collection: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (key, document) in store {
            guard let slash = key.lastIndex(of: "/") else { continue }
            if String(key[..<slash]) == collection {
                out.append(document)
            }
        }
        return out
    }

    private func batchGet(body: [String: Any]?) -> Answer {
        let names = (body?["documents"] as? [String]) ?? []
        let readTime = MedxDemoClock.timestamp(Date())
        var out: [[String: Any]] = []
        for name in names {
            let key = Self.key(fromName: name)
            if let document = store[key] {
                out.append(["found": document, "readTime": readTime])
            } else {
                out.append(["missing": name, "readTime": readTime])
            }
        }
        return jsonArray(200, out)
    }

    private func runQuery(parent: String, body: [String: Any]?) -> Answer {
        let readTime = MedxDemoClock.timestamp(Date())
        let empty: [[String: Any]] = [["readTime": readTime]]
        guard let query = body?["structuredQuery"] as? [String: Any],
              let from = (query["from"] as? [[String: Any]])?.first,
              let collectionId = from["collectionId"] as? String
        else { return jsonArray(200, empty) }

        let collection = parent.isEmpty ? collectionId : parent + "/" + collectionId
        let filters = Self.filters(from: query["where"] as? [String: Any])

        // Paper questions are generated on first ask, part by part.
        if collectionId == "medx_test_questions", let fixtures {
            for filter in filters where filter.path == ["testId"] {
                guard let testId = filter.value["stringValue"] as? String else { continue }
                for part in fixtures.testQuestionParts(testId: testId) where store[part.path] == nil {
                    store[part.path] = part.document
                }
            }
        }

        var matched = documentsIn(collection).filter { document in
            let fields = Self.fields(of: document)
            return filters.allSatisfy { Self.matches($0, fields: fields) }
        }

        let orders = (query["orderBy"] as? [[String: Any]]) ?? []
        if let first = orders.first,
           let fieldName = (first["field"] as? [String: Any])?["fieldPath"] as? String {
            let path = Self.fieldPath(fieldName)
            let descending = (first["direction"] as? String) == "DESCENDING"
            // Firestore leaves out matched that lack the ordered field (which is what keeps
            // `medx_vod/_meta` out of the feed).
            matched = matched.filter { Self.value(at: path, in: Self.fields(of: $0)) != nil }
            matched.sort { left, right in
                guard let a = Self.value(at: path, in: Self.fields(of: left)),
                      let b = Self.value(at: path, in: Self.fields(of: right)) else { return false }
                let order = Self.compare(a, b)
                return descending ? order == .orderedDescending : order == .orderedAscending
            }
            if let startAt = query["startAt"] as? [String: Any],
               let cursor = (startAt["values"] as? [[String: Any]])?.first {
                let inclusive = (startAt["before"] as? Bool) ?? false
                matched = matched.filter { document in
                    guard let value = Self.value(at: path, in: Self.fields(of: document)) else { return false }
                    let order = Self.compare(value, cursor)
                    if order == .orderedSame { return inclusive }
                    return descending ? order == .orderedAscending : order == .orderedDescending
                }
            }
        } else {
            matched.sort { Self.name(of: $0) < Self.name(of: $1) }
        }

        var limit: Int?
        if let plain = query["limit"] as? Int {
            limit = plain
        } else if let wrapped = query["limit"] as? [String: Any], let value = wrapped["value"] as? Int {
            limit = value
        }
        if let limit, limit >= 0, matched.count > limit {
            matched = Array(matched.prefix(limit))
        }

        if matched.isEmpty { return jsonArray(200, empty) }
        let results: [[String: Any]] = matched.map { document -> [String: Any] in
            ["document": document, "readTime": readTime]
        }
        return jsonArray(200, results)
    }

    // MARK: Writes

    /// `mask == nil` replaces the document's fields; a mask merges exactly those paths.
    private func writeDocument(_ key: String, fields incoming: [String: Any], mask: [String]?) -> Answer {
        var fields: [String: Any]
        if let mask {
            fields = Self.fields(of: store[key] ?? [:])
            for path in mask {
                let parts = Self.fieldPath(path)
                fields = Self.setting(Self.value(at: parts, in: incoming), at: parts, in: fields)
            }
        } else {
            fields = incoming
        }
        let stamp = MedxDemoClock.timestamp(Date())
        let created = (store[key]?["createTime"] as? String) ?? stamp
        let document: [String: Any] = [
            "name": MedxDemoFixtures.documentPrefix + key,
            "fields": fields,
            "createTime": created,
            "updateTime": stamp
        ]
        store[key] = document
        return json(200, document)
    }

    private func commit(body: [String: Any]?) -> Answer {
        let writes = (body?["writes"] as? [[String: Any]]) ?? []
        let stamp = MedxDemoClock.timestamp(Date())
        var results: [[String: Any]] = []
        for write in writes {
            if let update = write["update"] as? [String: Any], let name = update["name"] as? String {
                let key = Self.key(fromName: name)
                var mask: [String]?
                if let updateMask = write["updateMask"] as? [String: Any] {
                    mask = (updateMask["fieldPaths"] as? [String]) ?? []
                }
                _ = writeDocument(key, fields: Self.fields(of: update), mask: mask)
                let transforms = (write["updateTransforms"] as? [[String: Any]]) ?? []
                for transform in transforms {
                    guard let fieldName = transform["fieldPath"] as? String,
                          let append = transform["appendMissingElements"] as? [String: Any] else { continue }
                    let values = (append["values"] as? [[String: Any]]) ?? []
                    appendMissing(key: key, path: Self.fieldPath(fieldName), values: values)
                }
            } else if let name = write["delete"] as? String {
                store.removeValue(forKey: Self.key(fromName: name))
            }
            results.append(["updateTime": stamp])
        }
        return json(200, ["writeResults": results, "commitTime": stamp])
    }

    private func appendMissing(key: String, path: [String], values: [[String: Any]]) {
        guard var document = store[key] else { return }
        var fields = Self.fields(of: document)
        let current = Self.value(at: path, in: fields)?["arrayValue"] as? [String: Any]
        var existing = (current?["values"] as? [[String: Any]]) ?? []
        for value in values where !existing.contains(where: { Self.equal($0, value) }) {
            existing.append(value)
        }
        let array: [String: Any] = ["values": existing]
        fields = Self.setting(["arrayValue": array], at: path, in: fields)
        document["fields"] = fields
        store[key] = document
    }

    // MARK: Helpers

    private func json(_ status: Int, _ object: [String: Any]) -> Answer {
        Answer(status: status, body: Self.encode(object))
    }

    private func jsonArray(_ status: Int, _ array: [[String: Any]]) -> Answer {
        Answer(status: status, body: Self.encode(array))
    }

    static func encode(_ object: Any) -> Data {
        // `JSONSerialization` raises an Objective-C exception on an invalid object; check first.
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return Data("{}".utf8)
        }
        return data
    }

    static func jsonBody(of request: URLRequest) -> [String: Any]? {
        var payload = request.httpBody
        if payload == nil, let stream = request.httpBodyStream {
            var collected = Data()
            stream.open()
            let size = 16_384
            var buffer = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: size)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            stream.close()
            payload = collected
        }
        guard let bytes = payload, !bytes.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }

    static func incomingFields(_ body: [String: Any]?) -> [String: Any] {
        (body?["fields"] as? [String: Any]) ?? [:]
    }

    static func fields(of document: [String: Any]) -> [String: Any] {
        (document["fields"] as? [String: Any]) ?? [:]
    }

    static func name(of document: [String: Any]) -> String {
        (document["name"] as? String) ?? ""
    }

    static func key(fromName name: String) -> String {
        if let range = name.range(of: "/documents/") {
            return String(name[range.upperBound...])
        }
        return name
    }

    static func newId() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<20).compactMap { _ in alphabet.randomElement() })
    }

    static func fieldPath(_ raw: String) -> [String] {
        raw.split(separator: ".").map { $0.replacingOccurrences(of: "`", with: "") }
    }

    static func value(at path: [String], in fields: [String: Any]) -> [String: Any]? {
        guard let first = path.first, let found = fields[first] as? [String: Any] else { return nil }
        if path.count == 1 { return found }
        guard let map = found["mapValue"] as? [String: Any],
              let inner = map["fields"] as? [String: Any] else { return nil }
        return Self.value(at: Array(path.dropFirst()), in: inner)
    }

    static func setting(_ newValue: [String: Any]?, at path: [String], in fields: [String: Any]) -> [String: Any] {
        var out = fields
        guard let first = path.first else { return out }
        if path.count == 1 {
            if let newValue {
                out[first] = newValue
            } else {
                out.removeValue(forKey: first)
            }
            return out
        }
        let current = out[first] as? [String: Any]
        let innerFields = ((current?["mapValue"] as? [String: Any])?["fields"] as? [String: Any]) ?? [:]
        let updated = setting(newValue, at: Array(path.dropFirst()), in: innerFields)
        let map: [String: Any] = ["fields": updated]
        out[first] = ["mapValue": map]
        return out
    }

    static func filters(from clause: [String: Any]?) -> [Filter] {
        guard let clause else { return [] }
        if let fieldFilter = clause["fieldFilter"] as? [String: Any] {
            guard let pathName = (fieldFilter["field"] as? [String: Any])?["fieldPath"] as? String,
                  let op = fieldFilter["op"] as? String,
                  let value = fieldFilter["value"] as? [String: Any] else { return [] }
            return [Filter(path: fieldPath(pathName), op: op, value: value)]
        }
        if let composite = clause["compositeFilter"] as? [String: Any] {
            let inner = (composite["filters"] as? [[String: Any]]) ?? []
            return inner.flatMap { filters(from: $0) }
        }
        return []
    }

    static func matches(_ filter: Filter, fields: [String: Any]) -> Bool {
        guard let actual = value(at: filter.path, in: fields) else { return false }
        switch filter.op {
        case "EQUAL":
            return equal(actual, filter.value)
        case "NOT_EQUAL":
            return !equal(actual, filter.value)
        case "LESS_THAN":
            return compare(actual, filter.value) == .orderedAscending
        case "LESS_THAN_OR_EQUAL":
            return compare(actual, filter.value) != .orderedDescending
        case "GREATER_THAN":
            return compare(actual, filter.value) == .orderedDescending
        case "GREATER_THAN_OR_EQUAL":
            return compare(actual, filter.value) != .orderedAscending
        case "ARRAY_CONTAINS":
            let values = ((actual["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]]) ?? []
            return values.contains { equal($0, filter.value) }
        case "IN":
            let options = ((filter.value["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]]) ?? []
            return options.contains { equal(actual, $0) }
        default:
            return true
        }
    }

    static func number(_ value: [String: Any]) -> Double? {
        if let text = value["integerValue"] as? String { return Double(text) }
        if let int = value["integerValue"] as? Int { return Double(int) }
        if let double = value["doubleValue"] as? Double { return double }
        return nil
    }

    static func text(_ value: [String: Any]) -> String? {
        if let string = value["stringValue"] as? String { return string }
        return value["timestampValue"] as? String
    }

    static func equal(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        if let x = number(a), let y = number(b) { return x == y }
        if let x = text(a), let y = text(b) { return x == y }
        if let x = a["booleanValue"] as? Bool, let y = b["booleanValue"] as? Bool { return x == y }
        return NSDictionary(dictionary: a).isEqual(NSDictionary(dictionary: b))
    }

    static func compare(_ a: [String: Any], _ b: [String: Any]) -> ComparisonResult {
        if let x = number(a), let y = number(b) {
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        }
        if let x = text(a), let y = text(b) {
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        }
        if let x = a["booleanValue"] as? Bool, let y = b["booleanValue"] as? Bool {
            if x == y { return .orderedSame }
            return x ? .orderedDescending : .orderedAscending
        }
        return .orderedSame
    }
}


// MARK: - Offline playback check (screenshot runs only)

/// `-medxScreen player-offline`: writes a tiny finished download (two 6 s HLS segments, a test
/// card with a running clock) into the real download folder before the download store loads,
/// so the screenshot job opens it from Downloads and plays it exactly as a saved class plays.
/// Its stream URL points nowhere, so if the saved copy were not what is playing, the shot would
/// show "Playback Error" instead of the clock. The player logs `[OfflineCheck]` five seconds in.
enum MedxOfflineFixture {
    static let videoId = "demo_offline_class"

    static func install() {
        let dir = VideoDownloadStore.directory(for: videoId)
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(playlist.utf8).write(to: dir.appendingPathComponent(VideoDownloadStore.playlistFileName))
        for (name, parts) in [("seg0.ts", seg0), ("seg1.ts", seg1)] {
            if let data = Data(base64Encoded: parts.joined()) {
                try? data.write(to: dir.appendingPathComponent(name))
            }
        }
        let video = RecordedVideo(
            id: videoId,
            subject: "Anatomy",
            title: "Saved class (offline check)",
            faculty: "Demo",
            durationSeconds: 12,
            streamUrl: "https://offline-check.invalid/none.m3u8"
        )
        let item = DownloadedVideo(
            video: video,
            state: .completed,
            quality: .standard,
            resolution: "256x144",
            completedSegments: 2,
            totalSegments: 2,
            bytesOnDisk: 89488,
            createdAt: Date(),
            errorMessage: nil
        )
        if let meta = try? JSONEncoder().encode(item) {
            try? meta.write(to: dir.appendingPathComponent("meta.json"))
        }
        print("[MedxDemo] offline fixture written to \(dir.lastPathComponent)")
    }

    static let playlist = """
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.000000,
seg0.ts
#EXTINF:6.000000,
seg1.ts
#EXT-X-ENDLIST
"""

    static let seg0: [String] = [
        "R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////9HQAAQAACwDQABwQAAAAHwACqxBLL/////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////0dQABAAArAXAAHBAADhAPAAG+EA8AAP4QHwAC9EuZv/////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////R0EAMAdQAACDNn4AAAAB4AAAgIAFIQAH+QkAAAABCfAAAAABZ0LADKYRBATsBEAAAAMAQAAABQPFCoRgAAAAAWjI",
        "QjLIAAABBgX//3vcRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY0IHIzMDk1IGJhZWU0MDAgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxl",
        "ZnQgMjAwMy0yMDIyIC0gaHR0cDovL3d3dy52aWRlb2xHAQARYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTE2IGRlYmxvY2s9MTow",
        "OjAgYW5hbHlzZT0weDE6MHgxMzEgbWU9dW1oIHN1Ym1lPTEwIHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTEgbWVfcmFuZ2U9MjQgY2hyb21h",
        "X21lPTEgdHJlbGxpcz0yIDh4OGRjdD0wIGNxbT0wIGRlYWR6b25lPUcBABIyMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRz",
        "PTQgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0",
        "cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlpbnQ9MjAga2V5RwEAE2ludF9taW49MiBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAg",
        "cmNfbG9va2FoZWFkPTIwIHJjPWFiciBtYnRyZWU9MSBiaXRyYXRlPTI1IHJhdGV0b2w9MS4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9",
        "NCBpcF9yYXRpbz0xLjQwIGFxPTE6MS4wMACAAAAAAWWIggY/xFYCCcdhwAHj6PsAMeXPK+y4n19HAQAU0gx671fZRq1kFHsWsj3re950eeWshx5+bPOz2x5s",
        "rRvoEERXhC8ACAGc04iPAFL24/PC2hWQe7pgKSyCiuLwTREYiGjM6IS8MXvOr7fwAx5c8r7PeyNR4f0ezb1vPekXu3UhdVUrCT1UbPbnKjssKvNQBB8qfe5v",
        "XO/0VS9FrAg6v/siKxFQLGjt+I3//IQ8u/K+g2TKY2/8eVzzg88tMhx5+c+Oyx/OVnZYN9kajy2ezXolnGov1kcBABXqGSFYSnKoUeXW0KyhVf78BgUlhMFl",
        "ArqaqwbJiri/qIjiLpE+1fgE3nl9bMh53/IzeevrEDLs8tZKPVGz25yo7LHvedHnlrLjy+sz9WNzlM7LBjAMPm2Pdf7RLSsbUz64pecqYMenZb//phTZnDan",
        "EVARzs82RQh8+bLdDz4XLCUxp0dIxOvM/qEX2pm+q+ZF/Rc4yK+y50RNRE3siaVPNwRPS5WzhF9soZEktI5gjoOWHeBzAYwLRwEAFkCtoERlAiMgV8thiKW/",
        "BetGlEfhtTjMPS34bFsGAnkRlWoCX99yDmvJLqCxW3EACDzEAmvNoEMgtXOLPXH54zx4p3noUAAQ1Y4AAhTRwAD98ZBAAPLzYXwMOLA8eqJLC3ogFhQIs9D7",
        "QyLcRkIJL/CF77sPPCrojLw//grDU3xI4gABoAFmhmhA5DNcw5DNczw/47cTgAeAQ/BUCARCjB7w3wlJXMpK5nV7h0dC0a2ZXBSf/81DwiBHAQAXindAd0MU",
        "c6FXR3//pRDjPfvNkOlN4ywZX5mO/hLZGBZp6O/85Yvp04JoFCptqCW7RcBFbfq3JrzLHJg1mf1Lxxp+GgWAoECpWkFYnCJmUIqmWun8UtJHgaXBsBiMHpS/",
        "368QmgwAMFy2/Oz4X/u8rk9m0437v2vTyUjIH+thfXjMGW8zBnemCmvDDAP+CsOZtUSaAwA8M3m3gTVJoFmcsPOvoXQgAaqtqPf2/8UwhICFrWARHehdqUcB",
        "ABhiATB0MSjRa19P8f8B6Dqr6qLUFH21JvBt3CqcvC8MIrgsFZX4LDGAK4P+CJXog+qByY5fAkU64GI8EXdSnp//CoMGCTCDgRHdPCjzDhcf4Eopc8E7QVsf",
        "wiGvxDj+Gvfv3A0SBsx/vEtlzOH//iHiLDqae+sDdgY55NTwplxpuLUBK1z8AJCC7PnCZ/LgZnTBrT09c0ICmITktOKYeGkzJszEzHmhtWtfwD/2CsJQYCqD",
        "iTliF+IXRwEAGd7Gdi0CMUYXQMgn9Fvb/+EkyCmjAlGXPCu0Fy4/wIi3TwS8w5Y//BYcA2Gtw6AD2/DAcNDAHBrzvFZy//xxDwCGzvxa/Ic+t8Lsstf6+X4K",
        "o3CsT/ARem29+HH/hpJX6pCqB1G230APsCIl2PFTAZ33BX/uFmg0y3/1006BhxfgDDeRM6rxAhHlpgtq666enrp67+OI/+wRMHE/xAXiPacYwYgOpyYPRELW",
        "sBXZ/U4FiOGA/6DQtr9HAQAaaiNUmnrnoZmsfxGDWyc//+JB5F/N9rQOGP/4BMZmiNPEEM0uK4r4fhx774IYUgMAJ4AGL2na3c7pt9wxaDD8cQ+GgVrpAcxh",
        "EPOmM95om/UmdDKA6rjb7X+oK66d09dPXV0y1xTDwapnNmYmYrUVDRsEtCASrJpDOEhUEYCfVyLr/x4f2CIFQrd4hOIAAVaKYLxzAkaCKbZSaTdX4BA8k998",
        "FwP/0CpCKQSL7Pp9ABD93OsApKq7IEcBABtV3/wHD8OCv2gDhA4hzce7xSKpgXQ5DFcTJ/a/1BjXTxUFUCUgJEo304WIFLeVOBYFPAugLJE/s8sQqtZW+Fim",
        "6grrp6/4dzruw6Cw2NKZMpLRQMGuIRrA9SmXxZNAkapyFRiQHHgOAPm/T6iiWdUrK5ZVcsZbQGNhQSfTJuEL0R+/uZSU5imLLERkEskwtfnWMfuun3tZPbt/",
        "zsFIOAASBsR9otddPFQURLiXgdT7wIbT7V8VwHQHRwEAPE4A////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////9D0u/HUl2r/phOoVrp68mZEnMecY4F1GiGcOu76g6cKb2IeQauWLtRsCKsH0iCx5GYbFAYio3FQ0XADEK2ePy37bic",
        "s3XFU5bKcsz5lMGNdddPMu1LT1109cUw5HKP81sYkYS2tPTDdeBHQQA9BxAAAJTKfgAAAAHgAACAgAUhAAk/WQAAAAEJ8AAAAAFBmhwMfziAgVdQqSAInmz2",
        "GVgfBBSzf/wSC3Nvb4s2754UXbzwIMVNCJdCoDrICYmZAiTjHfMiCfL/4IZ1gDihfiAWAZK54bk9YAoRRvCfnPAG64/+Nd5hqYRPRxjwNlUfwfVcxibpVhWl",
        "wDw2yD6Zf+R/+nnfO+/nYK70cFXAXAX1rKvKjJPwvP4i/8RT45HGPqlYjP15FEcBAB4gScl6NS3bXW014FGGbvmmf4e7vle8DI4LwGl85gBYh0++Cv9/gx8G",
        "Odgw8H/J58ma4Q3gx+gYVSoceowGPgzzvMfv4lAt8CRJFfBf4MUDAqeDGKEQZ+C7w0cFwloQLr8Ab62R2b4Zg98n1/YeBQGwImsPBle+uX16QfEF4GTCAyMQ",
        "MvjhMkzcwkc2OEyVu5wkrYFEwKC8EyrTSTcgTdVesVcNoOPNamEWPGQoVGfAR+VUedaLX++vRwEAP18A////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////1Nq5n67JEz1/gkbN3xxfU7+PAQ//c/cP8MA",
        "SMQgZyBCDKITiBeY82PJnmPNjwmfCCwCELpyBdpvEGOr3yiIL+1wwAnlr5wVJ17UhD+Oufy05RvzsFOIWSBHQQAwBxAAAKZefgAAAAHgAACAgAUhAAmFqQAA",
        "AAEJ8AAAAAFBmioC3+dCtK1f/go3vuRDlZK6+bYK9JOCOAu/M8YKLfuPpSff4IZxwAvwOquf8ENdeDagXjcsngnBAtVVVX+EFaiVJ+n1gOeA9J6AT8U/gITm",
        "GPw/oIi6MVRNBjLwfHGEEAnC+ngm668vxeFoUnXI94Q8xB3gRVtk1nVfhHKMRiZzqoBtcPPLE2ZsUO+Zn4MRLwSk7Y3cBEcBABEs53Uvhgcq6rlQ0K9tt+Zq",
        "hBIxJGP6Zdbs2P8PoaFdA94OrH4U8gkVsM7o24Ff2L6oH8CoBRDJnjB1Im98kLrT//7oEaAhzpcC38PDem954Ma8NAsJ+ASxOvee/BO+1z8+JJf0GPCPqRO1",
        "GqZPvgy4ZOKrwj2Hw403g4N5fg/xbBausRxP/A0YhC+P0L/oE1H+CIct9/Al/AgnHIB/4AaC3zkzrwanpV+IubSG/UVxpobU/ASMl54LRwEAEuagw1Z5wVFR",
        "V+HovghV0HVqzTxJoKvxitm/ALZEMptC3BARZeCAiz3Z5psMvpW7kJHNpWdyPRQwDLUfaZKZ7TJTPhBB3m+gkF7OHiQeob+ylXMCb9nvYlcyk8fI1SriT93w",
        "H7+5b2Yu719hIuex/gH91Bs4+rxEedY/A/mKf/wIklnrRPvMebeEEw+yxEJScZMZ3GTGeIXs9phjb4g1Z7/lpEMfxwCQ4s6yL/pEWwc4YP2l8bl1hcZHAQAz",
        "tgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////SUdBADQHEAAAt/J+AAAAAeAAAICABSEACcv5AAAAAQnwAAAAAUGaOwLdescvwSEhnNQ95IvjH/BHCjwx5lF+rT3pkUn3X4FJBtReLiTQHM8GJXF3YuAb",
        "aa2U+DFhtveA0BuX8l+yp/BHWv+EEYdagbJPAkPp18GPgIIRiFpfAqyJQjwRHpwZqEGw7EAxVO/v9nDOcDAc4EftaXmVkp31vRWlWYQ/eET2abRL+RL/+en+",
        "BH7v2+MjttuD3kfgRwEAFULlJk/wKnQ8DN8LLNhskzPHX041y3psfhUNcFRgKjEtBXLJcs53xRpF3Tf/+g0L0D9yISH+01+CqrmWycEH/wFAwt48t3zhctRP",
        "Ry/EJbTz3y/AqYCwwd5+M4MdXBj+CsGK3y/9/wYrXQE4Civj4M/gMPwL2IOwSy0qBRzrQMQjkr0vgJz02+DH4M/gS+oBIc8F8p+SvEI9KsSDI4KV/QQS6NkT",
        "0vx3BeWTNaxgoKFD/AJTptdoBmRHAQA2IQD//////////////////////////////////////////66aynbrhqsn6wn8JIIlS34FSGhgr6Epr4E6Jm7V/geN",
        "EV+sCT/AkAxlVZAXFJeZfRp3zrwsi/V+lK/Snr/ACi66ksG2/ljXk9Wub1YcfyfrH/HXeGii74C2C/peBSN3nHd4ZuIfhUkAEGnk+Aj8Vr3/IIQK9toQc7Bh",
        "udHxwCO6z04/difcmn+Avjh0vVdX+JPCslHzQEdBATABQAAAAcAD04CABSEAB9hh//FcQBNf/N4CAExhdmM1OS4zNy4xMDAAAliiVFIi/td1nPv+u/xKePje",
        "alTVJCwxWJxWJxWJ491U0ZVMa1Xa1ZbFibNxnj8NvulVGrClClTtirMlWZJ9bKVRlUZXGSgYG/o39GBgYGBgYGBgYGBjZsGBkSIGBgYGBkSKWWWWWWWWWWWW",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWXv/xXEARX/wBEpLaynNkRwEBEbmyXNkuX/9P/7/HVy9e//9b/3+uuLvX5//q//P364vWv4//q//b461qdB29pMMgwMDA",
        "wM6JU9fqYr2E4tgRkYxGoio1xUfSKj6RUfTdxKg3018YjLObjU/JG9KYCbURmRRsijeijeiD0UQDzIoow8yA10Jip55555/lzcD/8VxADd/8AR7xGRBSqy32",
        "yeL+3z/j2udNS01Uu2krUB0tjjMju7u4gzVUlpt9eLNZJmshM/8fBk+/uQ9HAQESj4bHv7wjJ8Zhn9yD/wYO+8If+Gw77wj4+Mwz++gH+MwT76A/kzBfvoD/",
        "wYJ0aAj44cD/8VxADH/8AOoxEPZSeZ1U7xPn/+zX/z/JWtZfOskXtrMkF4qRIkSOs2BzoG+ED+rIOzjg4Ge79Olml6LF5zF5y4M0sREEupQWKUKMnz7HPbpR",
        "6AbJfEYDMtkvPIUKgpC+7z//8VxAEn/8AT4xACxrKwkaxICgn//7frOM3//e3/5/9b74yEcBARPvWjLkkulAA433CiwuXi1wSD6ICnLNEjlkB8oNLQGWeVQY",
        "k+GFgw8e9IYeweDNvDih7ylwDAx7zpT2FcdmNnnEjhvXqXOcL6RIEYoeULHARzCpBUuNU8xbymXGd28UyKe1jtGJNdg2Q/tQHlojDnnA//FcQAvf/ADwMREy",
        "MbNZPd3uf/h9v+v/N21nWM47uVz1K5uxEDRo1Syy/0Ofyv9+j4mCLVq1atTV1rDqrjr4qzcPzpVKuFOVRwEBFGee8pC7M0wzmaeaFcTXY/cNcwFbaeD/8VxA",
        "Eb/8AT4xACRbMxCWxICwn//jfpo//s/b/2/5b45ipIqzqoQD46KKF6q2o1zlzaurEdALPWoV5KDgjStJRUgoFEjPRRQaigxlrC5EzQQNGFDK1ysoa9ehQADH",
        "5JL4kdtkVsNbBWpZGACaMCKuTDYU86Q+ofSvOlSJydnIQa6lCMISqemm07BDt0//8VxACx/8APAxCsLEk+034+f/7X5HAQE1dAD/////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////n/v/+7iG+q78056d9TPXwCNKPkj5fL5HfjMDD5fL5bKtnEIQNhZQiG6bUf6d0FK+hQCJT46lLq7iq4sK7a9lVCWrt0dBADcHEAAAyYZ+AAAA",
        "AeAAAICABSEACxJJAAAAAQnwAAAAAUGaSQBNxfngI/g1dz68GNUBvz+FTf4HTHcyyAaamsn5P/Qhfh6Z+P+E8j8CBXgpVeAmq0QBMuBcrEcPgwrfX+X4f8BR",
        "TmQG4e+8COvz314I8vnr8NLf/hHKEEwTexwCZ94XZf4MQb/BerY/sf0/g5PrhluP4e3H0BQAoqVO4Cf7n74n5btRlbsGQU7B9+Dn4N8SwQzfE8NHRwEAOC4A",
        "////////////////////////////////////////////////////////////BQVAYDV/FoUrweq2ieD5W7gKFe77wYAwPRCS8CimbBckVS/wXVgxBwfyLwh5",
        "sHpd5eDj6PMhEl4J/r2LfDxNE4x3zyoQLr8soQZfPyE2XtCWtXvUY3eo45fnkQHd+CCdpvvw1d8BbBPK03/fYiCuuAlMfBQkOo0BefWyg5xUGrlk7Lbv5zwT",
        "z/dHQQA5BxAAANsafgAAAAHgAACAgAUhAAtYmQAAAAEJ8AAAAAFBmllAUcWX/CP6AyT1/DowV8BK1FLSS8V0edeL/3XnQCCEyfzl8e5O6aE0Pk8FGtVqpUVS",
        "fL/6xaL2CE5kBv6YjTLq5y8956Av4734RyeCKq50dVwZ65fCteqc+DH4MeSA2eTiq6/8+L/D7TfWv1quDvOy5+f5K5PVtcG8GWLegC5deZeAj88FNYMOEECr",
        "Qpo0/BOEbMJfwUcBADqCAP//////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////4UEEiXkD9W9xS/gxqSk4MrfwJB+RGf4faYsBVcC9r61/J6g",
        "LdZ4AUY7/sRBHXAQ0X8whaP1R0EAOwcQAADsrn4AAAAB4AAAgIAFIQALnukAAAABCfAAAAABQZppgFHFk/v8EP9QBQBeC/KMQdFdorzh79YcrTf/Cc5oCYfO",
        "8j8s2GHqL6qJaEtfi2bc2scyelMA1IP+fEr+TBgHVc8INW+CE64dl89AGZLn4LwX535fEwW4jib8QhPhN2X/nhtAsr49a+DFTK+DPqAi+uIvmwRDK9W5nSRL",
        "WbqoCPu/rOYSkBa/FsHnT1BF19ffYhD9egRHAQA8hgD/////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////SsctqiLX1kXew6cdkQBR",
        "eUnA8/IsFaguUqddHghlvl4CKqaARVRqnWg8dOtfznh+KkdBATYBQAAAAcADDICABSEACd2b//FcQBBf/AE+MQAoayoYUKJBsFBP//M+Va5//i9f/P+mWyTf",
        "GQSXCrDmkt0TrlzRGJblK+hyYJSmQaYUNrKlTmqTmiQm601D0ZWudnDtSzx1dZyqsthmkwH9uCDsQkNm45ykxtJ22HNBR5be5JUFH+Shda0jVOVmqW8+4wjq",
        "3P6bwP/xXEAK//wA7DEKotb6991z4+f/7Xz//D/1qVpdKuqj17Hj4wPVRwEBF/Mc8885zqjDc5551KVOc7Q3nVGuiuhfPSlNBTFdalBO10Sm9S0VXEZRX5aK",
        "N4Wtx4D/8VxACv/8AOoxCqLU3Xje+/n/+37//j/+kVdNNySV68ye/mhme3SPPPPJSwwD37eeeZI9c53sHK5j0zdRr140s3OEnky+kIwzZ7KyRSrN9QxECC5I",
        "Snz/8VxAC3/8APAxC0KF5XOb8fP/9v5/9//3qtSVOOdZPn2ue/wGCzHV6/r1OeEgXT5HAQEYv69Y/1h64UBQaFHUoLmrjnOdd9Z2kKvZIXtCItfxU8pytcZQ",
        "2/ei1xtvfv/xXEAK//wA6jELYnO5zm+/X/9z9P/f/9bRdOOUkfb4vPXxsOIekR3d3d3SGMDIiii7uUUUUk0SHg4UTEd50DuexIu9hkSvecgmNx6Z3oDEKEUZ",
        "Q1AK8P/xXEAMX/wA6jEIIBdRJNo99759v/6X/b//1/5VxUqdc1LVWXJvVChE4omJiY8/mc0P7JCXRUcBARkUUUGoWag1DOeiCK0TcyvK07dreETigbW0gjZD",
        "FaUr7uqh31Y0bck0opU63v/xXEAL//wA7DERFkJhqNzxmTv/0/P/3/ymalSkulbu5u6ELMpuXFFpY6mLzVssXttcWDYiii4kWV9XcpGwggMHMcstXnJC2yZ6",
        "SkPZiyd6UVrUtu7u8ulh0YUECetw//FcQAw//ADqMRESQjiwxivVZXP/0+3/t/1tcUqXVNetaxrYbSNXaYkJ+c63RwEBOoMA////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////2L+l/bK8pJC99N303X/QNtvNt7CxXLBytrlHWVmz2hEx7I9jk55FTXVTK/Hw1YULhBnT4BHQQA9BxAAAP5CfgAAAAHg",
        "AACAgAUhAAvlOQAAAAEJ8AAAAAFBmnnATcpP5fx+bzwEXgdVc/56/xnP4f+Hp6FTf4HTHcxEjzdnn8CF9t87/++BpD84qAnH9MOJwyTfP4QWBIkEoTweewdC",
        "Mw1HIIMTCQ5dwdqf+gXnqTU/6P/H9Etfir5ujwVxVfh78ffBqcFi/Dri/g5PXIsE3nt51hku8kBo8/Efd/XyQE6pE5NRlOQCAEOT5Pn/tSoy8EcBAD5mAP//",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////En+qVP88Eey+D65IDQ5PEIbyfJ5P1/zguSP452a31off58X8En5BwKk8h/8BgeSA0eT/zwR8j3JxE0AnZwRCJoi/gHrnY2TUcHcmoJZf4+Tw",
        "R0EAPwcQAAEP1n4AAAAB4AAAgIAFIQANK4kAAAABCfAAAAABQZqIgBNxs+egI/wJBap588KmwqZ/lgB8I/DM4xf7vJ3/5/CW35knz+WfPAOAfgEoq9icBGb2",
        "DS4L54DXUcGj+RzScRhGtS44F/gkBDo6wTgUVSrPngBACIaKuf8Q0q5/xAnl4RuoG9UqXBj8G+eC/n4j8Qn3/nBUkXk1PXqRP1vXBjz98BJyfU2rXNntHu+G",
        "/vm6U6h5ebNHAQAwfgD/////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////9OvGe/uAQ2vqfufm9SIRaS8BnTxAFkAQ/AJTkzXa/wNwRUbT4IVKn8v",
        "xGBvnMgL+Ex+ev1rL/+v8EdBADEHEAABIWp+AAAAAeAAAICABSEADXHZAAAAAQnwAAAAAUGamJATcYNkgHCtrEfeeVBd34BXNOnI7zwW+Eh7farpupvSwOOe",
        "mX4E3/dlCmb54Doi/o2uPzrppssT4QWZDaxn6WPxOEatITymr4J4G/nrn8fMGXSDKohSILD6nMLrwjmg1kjxuHhfuf8/Dmde64HH4N+f5/EwVxVfhQIZe//q",
        "9RARL4OTgov+Htx9wFCpk70pc/iIKZ/oRwEAMlgA////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////78R8R9/eg8JSzVwOWtvD3k1+5fiHRkh9Hr+EOgpiJ9RPxHxHU3ydV165BLz2eKZP4fu/6N8/3wjq9t/+GgY4",
        "96A3CX88AjOaNdr/1fcTxC4EXPd8I9z+gKAIVryVS4BHQQAzBxAAATL+fgAAAAHgAACAgAUhAA24KQAAAAEJ8AAAAAFBmqigE3IX/wED3hSA1cy8I6if8+X8",
        "AkfTV5Pj/noDfxeeKziioy/LA3LEZ6wlx8/7Cc/L9yuXu8H89f4CNVPctw3z0VfltZuRXmc1t5pONn8QgZ0Pg1DjSEBaIIsEMd00jorpoLD+i5/fPJJE16z3",
        "wKlnvNWNuhjbGcGKvk+ev/4MefjXfA416pcb2/XL4MVFzfBjz/Ed90cBADQ/AP//////////////////////////////////////////////////////////",
        "////////////////////////L9jOEWZBEa6L4TJhMn9a/Wv1t8F9xWex8Ej4vSLyfr/yfdwEBiEC3iviexcMKm804URN+I9ov56pF6WL4Mcn5l/AgnoCP8Aj",
        "O0j69qCE8JSYQVdOKV+KACvz19dZ9DPlRPSr/P4B+M9+ASDJ669J6SX8EQIta86gR0EBOwFAAAABwANKgIAFIQAL4tX/8VxADF/8AO4xGTIxmoREvVfbeu/H",
        "/x9v/n/ZVpl9comUkmwIQa6aswMjrprpt1v6r9n3/G8TDv92/fTnvU377oPdaE6Wo8zbGiuSG/fWqJsuWKxivBSsq0vR9sTWxcAvbv/xXEAMv/wA6jElpOM7",
        "c3zmvev/7O//0/EWLbu6zjvUrOKEyurour1N9b93nXi/5Ld+lalrDzyXnkvMed0sQlkgDyEDa69HAQEcC5iVoD0ie+h6HJHgiswdDZ1qaqh5uElEs+Ey7U5u",
        "Hv/xXEAMn/wA8DERFkJ4nay/fG5//c/T/9/7l1JOeKq5XetVu4Lx6l21IZrzXjnuAKUdpsqgPiAw/66uqecKOpdC+pQVGyuo53wfBoa16FLqgzjMLRt7dkGi",
        "ii9aP3BsXKUYpz7/8VxAEH/8AT4xACxrKiVVAUE//8dfxUZ//F8//b9b1yzirypJVyprAAJLf66hhUlyaIPBNEcBAR1Zf2+zhIJWc2BwbRgZn9T0mLMo5Xxo",
        "iyLFFjYUREmlkwUVS4shoOmBHs7Z65R3olWl7QItda21S3ilvvONz3lkJtCaLi5br9tjdMP914D/8VxACx/8APQxFYNnt3Pdz3z//F9v/b/8SSpcrKlvXm3v",
        "8AjdJbTExMTG3T7XIQts2bNkdmyiK2yNq7UdhYRdu2RK9uwvY2xXyWvGNMSgsLfhm2KDRW8u//FcQBJ//AE+MQBKSzI+BIJwRwEBHrCf//f2rzzX/0/T/2/3",
        "mJmsk1uVc1vVSA+z0VE5WXE2X9SOFL7GRQaztrleCw9cvU/mpQaqZlNyqxlillxZx9/ydJbVQFyKsuUcW8cL4oUMTnKHsC3gXloNgGA95Cwjcrz7S5D+XM46",
        "UcUz+loNKtSGpmdDRSjzqD5VSrEqvbL18P/xXEAKn/wA8DEKAyRXNd9+//9v9P/f/+FjOJ3q8uszqr+fYHqKHV/TduS7cQJbv03O7jWLStJHAQE/RQD/////",
        "/////////////////////////////////////////////////////////////////////////////////////5rYZ2Wl0dLErZMJQI5Ly+dy5yOVQsLNFBK6",
        "UO/A//FcQAq//ADsMQritN37vHfz//a+f/n/9VSJcrGt39vi69eYDqcyqnnnOeMwbnn+U4E55yQU+jZsUjgOGWJW9YKWi73WF4N5PK4qCFBiIgodLqeXgEdB",
        "ADUHEAABRJJ+AAAAAeAAAICABSEADf55AAAAAQnwAAAAAUGauLATcrivn9Uwqbnn9eCiqUTdHMedBN6r//j/hM+EfKIn06Pj+vhT3zYHHERYHOqcTxfp8Bw1",
        "CASkIESMxE/JgwBCrfBjxPxHEiYI5MGH4RQef9aO/BzU/z/EfE8R/EdBKnAkBIBIAkhdl9MGrl+388ZQAV0v0w66X+EVgSgvtN4Jv+fgxWq4M+YI6pT0XvzB",
        "UWbdRXf5RwEANlUA////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////4dl84eUkjj/8v4PvrByAUAP/6tU2qAL3PF18Py7LSn+cyUfzJABalPc8r4MOSCEOaqodDAgSLokmeDwZn/PffnoAfTCxseM9fqCG/PGsBH/lRAB2",
        "36krXA4BBRlEV8IQgttHQQA3BxAAAVYmfgAAAAHgAACAgAUhAA9EyQAAAAEJ8AAAAAFBmsjAE3K4r5/PTDhLuXhLuW5ON3DJFrLg1Bw+twtvsp/C6v8Knt8w",
        "ed4/knjPH8DPGWCb/gkUdc4F7sBB4fkwQAzzwjxXQ+DM+AeTDrlbuEjNKn5YL67jFxE618+/g1x6wraC7uF2Xx+XH8BECvk7L8quX4ni/rD7VOo901/08e7Y",
        "grO3/8G/JAaKmTk+fxEFtVnBYvh01EcBADhBAP//////////////////////////////////////////////////////////////////////////////////",
        "//87f3qUBIcfwPmFPLD0YqaTAjM+eTIdsfqMfJ6rwIP3JqMpyAQAl44GeM6AfZK/OL+MU8Wo4+GG5T5PEkITAoBH1rqBQW2EdsRbDAKX4SPwiT7H4CItpd4J",
        "+wtY/VctB/YS/DyP0y0+qKV9TtuSDDUBt8EC25vAR0EAOQcQAAFnun4AAAAB4AAAgIAFIQAPixkAAAABCfAAAAABQZrY0BJxsZwhi6t8HJxyKz8JT84/olrf",
        "i8d5/AJ+BL6QdX/noTv9t5TGwd+eM4yI7ivHu4glEVgUm8qFknlQPb6HU+j3iEolQ6a7Ikuw612Hpdi+C/4Mfgxx/AkFgrDJEJniBM9lwEBxndYzt/VsX0JS",
        "fgx+DPiPiO6o9fILD4aO+tcGHwYfy+tfrdWOBnz99qXnwYX8Tg1HAQA6rAD/////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////+q5+vBdb1T99RPUEdBADsHEAABeU5+AAAAAeAAAICABSEAD9FpAAAAAQnwAAAAAUGa6OAScZ5z",
        "GEw4R/RPiYzn8OGWsBGNjX6Avv/hOqQ+FY7z+0tv//hH886OPkD58ziII4ifnHw5AOAfhZl8G3Lj+VfJmX5W5fvDBr3P7/CEDQwSaLC4NwoRXMUSn+SQDcAs",
        "eK+N87l/ggiDsEtUO1IqDzZPtPgKH1R3vVGKQt8uO+N5az18I7bwq5U1/z/H+GZ5vL/wI0GhRwEAPE0A////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////z/xLvggBgrfBoeW+HdMo78v3956de2XdcCmpr88nDQH3L/7gKFTJ3rTLP/",
        "qmUvr+fEBj+fRfPrO+l74o/v8DKUCK/o8O5+h8NQEQEeFMvgyUtX96kTJ+3A4frbw0DH9Ujq/VuT5oS5+4BHQQEwAUAAAAHAAxWAgAUhAA3oD//xXEALn/wA",
        "8DEKAySc81vx8//2vz//H/71ETd3Kvc74t480L5HkvPPPJSy4WPc7zzzydafpkmV6zx9JbqTy1SzSyRWz9YE/NBBOeDdrxpVn0GUjaH3pKSk30T4//FcQAu/",
        "/ADoMQkSQmCpW85eO+//4uP/b/mF7tdVcmevNvn42Pin5Hnnnnvc1P9Lv7jZdPPPOo/VH+lzhRzn9ZzYfg4UrZtJYbbaWkcBARHBG8dp8ZRuptoWFAvkXKBb",
        "gP/xXEANf/wA7jEQ9lJZpISJ6rxxX/9r3/+/8xcjK1VROeDOsGAALIiwMWkY3ZfYaL7WQeZHCwMnlp7+Wm79s5CT9pAegieJJapqpzz2TtPiHod7gk4VOG+f",
        "VT3elBN+JhOWxyTKMgFg1I/3//FcQAxf/ADqMRD0Rwk8zq3x9r3PX/4fp/5f+Wqi2a3K6yt8Su+gXmGJMAwMLUFsDuMbyj3shL6KKI8KRwEBEihfru6FUVmF",
        "AEEazmCbF+qlha6+kYK45xW44i4mO8JwxFU0WbV4//FcQAwf/ADsMR2lAyqk9c5Of/7X6f/b/nUReTNTm5vjJmqGZmmMolMTs27Nrz+d/bBIiiKJCAUUTkXJ",
        "iJiAQ9Fsx2Ag+rCEXHkMGa+hvxNchAL6t41PDhmVXzKpnA1u//FcQAx//ADwMREyMnmdrbxWZ4/+Pn/y/5uSLb65uK781ru8EKqlRcyXTIS+0/omXsFHAQET",
        "IQooooWuhYNuBlmXpcSoL3B7ALQuUJv4JFca+qneMWrzOtrGW8k8BOM8WFoSIrWvwP/xXEAMH/wA7DEI8EkI2TNfNc3v/+19v/t/taKrjBdN61XfmhvpLmm+",
        "XyRpM6Z3le2v6vBFv9HnYr+iELwZNWmpiQhBVekrbYCEDwfhH3mK+bUsTngGc5XhSrK3xfm/bv/xXEAMn/wA7DEI1mJppUv5zW/f/x8//b/FSEhl3XOdSc3Q",
        "V9NPmkcBATR6AP//////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////9eZIUSiiUQ5978ZcQGND0eeeeY8xiXr3mbXucG7r7wHB/+9vboUmUmG0o7GC8YVwY0",
        "qZMl5+AGPaRHAXrwR0EAPQcQAAGK4n4AAAAB4AAAgIAFIQARF7kAAAABCfAAAAABQZr48BJwqIWJO+eH47hM4eXwznPGJXhE9BmfwoxO8189J9d2o7HT85f/",
        "gQNf94cNlwuBW08Doiy/OeH5J/ER8jYrgF/ODIISMgFyipf83nr+YKjJEY+5hAPwjNhwAQmffEOkesDmMDANJh2pZZWQF/LLABXgxyfLX/8GMTzH84+Ze/2o",
        "nWfIdDsMsvhl8e7/BZX/q5Y/6EpHAQA+hAD/////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////05d/8GPwY7vgca4EZfmX7/X3693Sgzp",
        "8FVRf/Z2i9epEppgQAQ66boFXvVjkz+/ELG/uEdBAD8HEAABnHZ+AAAAAeAAAICABSEAEV4JAAAAAQnwAAAAAUGbAAk4teEfhGdrlouK1/BBwitJ8LnHOfNt",
        "E3H9Etfm8K19ed4uI5bw0uXgUpgbjXP/BiCGXs9Kv4biTl58QM6/RhYXrVcDBqvPCnDA4GoDFSzwmeB0hyx4Zn+DH4MeP4ntYkXzw2HiTk3w1DjsL6zxrEAQ",
        "q/iXQdPdfX+r/rfXBeCarlD3lLxV/HvAa4NuX49/4G4cf3CLRwEAMHQA////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////5t/4MFzcgEr2BGAQivUfr3H0edPu2PJ",
        "/XVfWeExk8W/1AwqC/2lBIBUB4eZCnx7xrXWO6InKtwIAFHWMcnzfH9cdJBHQQAxBxAAAa4KfgAAAAHgAACAgAUhABGkWQAAAAEJ8AAAAAFBmxAJOVxHz+el",
        "H+PXPqgCiejjF/csTeduIdvaWiF5mX+p54Q89faDztILdpmr4IY/z1+ErfNv1/NHeeCWL84JgPmBhywj3CGiljAjM+eTI7YIif5Pl8nuK+A4ALAMQYqgNLSn",
        "r+Wi/PA+bpiO/J8IDR3ASPqBsN2HgEgr956O/hI9jfwj18skBo54MeEOUTPXBwg8gH1Rw0cBADIsAP//////////////////////////////////////////",
        "//////////////9cFE8Q6PcTSQr3P5161UbqsWq1ngwC6Il22/yfY58V5/AJ9sSLPvPX4at56k14IHk1o48meiWv4fX5vgsPCzzDiBM8vS4WBkr+HgYK/9Rl",
        "n8APj2a5l+M/s8ifgYqcnkk+TVOsmtDf3J6msJcDsgHFPNokmfqC88Bie3PJkhrDv33UVhPBmEFrn5vqR0EAMwcQAAG/nn4AAAAB4AAAgIAFIQAR6qkAAAAB",
        "CfAAAAABQZsgCThUQsQPZScRc9FRTPmfCHCagJjHvAFCJGeCn94CNSC+vfn44v1/+f9+Izd/PrBh+t756T67tR2OPDtcGGPgshIkOFMxQJHqeBBufAjz54BO",
        "O+eeS4CR76wQgxk89f4RNz2eVP6CLzrA/R7uGUD02i3/vPB5PCczIibiegAw++vY9nyjQAqPR3wiDCrZK+f+bPoqeCJHAQA0MgD/////////////////////",
        "////////////////////////////////////////////vsfwj3Bg0fPBfd9r84MHHBN/z/Bh+qb4NOcAgk+gtP2H1e0/mJP98t3vhDPEE0l0VfjrQikbmz8w",
        "82/PsS7/HwfVwYrr4MVY/x75AR5t4MVLj+UhMvvlFS/wYLX61WtROr8TAQ3Nnipfzb/7/R4K6+i9YMv/PoOAk3guHqCUfqRqiPiOIkdBATUBQAAAAcADMYCA",
        "BSEAD+1H//FcQAzf/ADqMSWE8zsZ4rjxz//F7//v+8VC0TJfMtvjAm6mrpV1v5G/dv849E9Fv9l16CeeeeeuecHOo+xSsDmSezRahCgc6Olgt8uqp6HirE2s",
        "dLMljaim83CuGtLXw3Xgg2OA//FcQAwf/ADwMQj2UliteX63zxX/9z3//P/CoSZaq08dXPWoH+MmnF55ApuS4wpe5jOzjg4G79L1yZNL3exHfp78RwEBFkOF",
        "3I7hJZNArJPHaozDqV7zfeFcVpWNoQzBIrPbwP/xXEAQP/wBPjEAVqRymQT//5/XTK/+v2/8/9q43Sq6VXGLZqoAA71gcodAnaGuCT3wwrJgcBIjlkR8oOpG",
        "Bh79c1YkvTLest8HpFjy9OUi9kGL2XgyjmcmUiKOEpb/zy1XKZ7lRKEli6QN9WZqJdcL/GXHfrrrdPVDHEhmKC9r3v/xXEALX/wA8jEJDkGxb5b3P/p+3/n/",
        "10hHAQEXpqVfOqrnqT15oIek7kRRRaHLn/X+U+7BFXV+f56oV/NDVBLHZXO1Qqaow6wlDPWkhfASZ109ylayFi1fvpAVvPj/8VxAC//8AO4xES4xsvbfPPd/",
        "/xfp/7/+V1xKvfFZIevOs9fWxkkrHsJppvlL0PePakg2bI24cPXK0eGyJbDH45eiS1u0aWnGyNhmP2i2ZY8C13X1jETYI1w61JIPT//xXEAMf/wA7jEQ9lKZ",
        "jRvNs5/9P0/8/0cBARjN3FW3qpDJc71BdDpUUQMDHUyVzF+tdVi7vKADCI+XjFVNEhFU0SAgqlkD8wBFZNIkjqRl5gjXCR0gDixBBdrh7HmSl9sSJJ4Oz4D/",
        "8VxADF/8AO4xCPJSWa18zxh8//2OP/t/i6OnPGVXFPXm3PGw2ncl576a3Jy5LV/slf3jIhHn9G3nlsTed69aUgMeteYWOObAnXrQrOPY3TnE170dAwas3hJQ",
        "nDlNLTIC/P/xXEAMn/wA8DEIRwEBOV4A////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////9lJxoax6rvj3/+uf/p9SQuKSrrcu+/Owu7qnnnnZqTOcBJXU7Pi9CYDDzzqOpSlKnPOc55TKfjUEhM6lRvvO",
        "KzcRyayRjJCutU48mSx+JNm+lgkm1y0e34BHQQA1BxAAAdEyfgAAAAHgAACAgAUhABMw+QAAAAEJ8AAAAAFBmzAJOM9SiKj6gCogQs0ZB9l8/84w4nFSvmHf",
        "CE2eASxrv/jT2u9Zvp/PoDfwH77nj+EfQ8+JT+zBH4/P7rTx/RLX7vHeeAi8T3/AlHph/4C7/Y8HB6QfAWupu0sV//j1NwMKDBwxCJoUXhxOlngTPJG+Iglq",
        "P74OPg+7U4cEnv5UA5c+dAYGql0tcQ7/cDQeMFBQFW47wkcBABZ65ywBPulo2371OjrEZ4DoAQanL+B5Cl/IT4j/9iPr3NnlFwTb2ET9j+CYGAaNy8BbBGc/",
        "1/wgo74GdAZkBKM9qqxBhy/6ZN4tnN+N/q3iwYn5Crf5LCrYz5/3w/ZvQ/4ylzaGL7uAoebDgnieICP8BEW0u88cccmH+T0MlCY1oOrEagGXwIS18QfXyowj",
        "1i/h73AUAIrv24vriePgIj1PZ87iL5L1RqquCkDlPQMPf+BGZ88j8Il0RwEAN5oA////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////GQjLbX8Zd0HZ4MF55ifh9YsIL6LZN/U/JXnYKZZHQAARAACwDQABwQAAAAHwACqxBLL/////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////0dQABEAArAXAAHBAADhAPAAG+EA8AAP4QHwAC9EuZv/",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////R0EAOAdQAAHixn4AAAAB4AAAgIAFIQAT",
        "d0kAAAABCfAAAAABZ0LADKYRBATsBEAAAAMAQAAABQPFCoRgAAAAAWjIQjLIAAAAAWWIgQHuGLAGB7PAAeieOQJu99wmnF7n3EbvfcLO6DyxnKHZZMdh6d0H",
        "onPHZZGcodlgHwGCAADE8i1HK6IisgCOtJAkipZFK49aIoIjF0YGuirbf19x/ATf77iZ/4iHZ3UKbUd1ygOzjdEHlrqy/BTU6JZHAQAZ6whq/ujfd3dOOUU0",
        "iIgPgyPavi/vubd/vuINpk2/r7juI7g8vqP8XLDhE3Y0kz/y77HG29IoASF36Sv5dMaKYNP7sgEp02F2nrFpMREAEQR2VWOyvwE3++4zL139URdPy7fZKrV1",
        "XbjSSFyuhCobyd0jGND07uZBhg6nLfEzLEHWb5wHs/7Xl2IxEc6PmyDo5merJ6KjvdpmORqUA267RrI2cROttDRXFo2a1aR0N8HbTuMYFoFH5UcBABqMAmYs",
        "EPlnBlti+0aU14XTiJB62/DYtgwHtrgKsvXopRlDMX2mIBHxCa20PgyLVz7mJ+VFR4VFAAENWNAAEKZDgAH7///DDgIIvUT84QLEKBQlWB5CuRALF//p+HRa",
        "e1vCIA1GCh82AZd72Rh/AIV7TB8RuFTYUmfh//BWab4kcHAANAAtawOQzXMOQzXM8Pv4u8AD4Q+wVBYQQUYNrEJrEKdZ0L0di0ZLTOIT/8SWIksHQRLxx9o+",
        "RwEAGz/nI3yDwTc2Syl5jJPeRBv9Mno9/roSLbWiALMV3/e/5/79LT1xah2mFiAtzWIBYiAWP/+vHrSV7WtK9QxIA0GoDUYZ08gnXPGtUxB1HcObg0m4a/k7",
        "l0mbyjOTup668LBgH/BWXNkPHAwDQje7eATVJoFmcsPa+P/hoFnieCmEJAQ9awCI7ZC7UsQCYOuPa//D+CvWG8gSRDAwDUCuWUSluhiL3TyEjueH8P4K/D3h",
        "e8iG0qf/09NHAQAc1xTHh2mF2x2PwvCQCVrn57//EBSDCvtGQ9r38QY6vfGMxZBMUEJBXrmgGHj1wCK+iECFvUiME80N+pC6p3czNmmbXp/1PMxxP1dPXTzP",
        "aLhKaIC2u7trfNt39q3tHtrfNhUyYwUEpg2bVzDckgff77EHR+KbgIgH4EK1XOACEz75HgqoSLOFD7b4TIMlLy4ZkGpy11BXT09dPM9lLM9qQ2nimCiAi8W/",
        "FUXAkLOZRzhhf+LQ4MMuCkcBAB0BhENimesG05iGaa69IBHmMvxm2B1mBgA5hJY+E17OcCwHACLutlAKs3Cj6BIWLzgTINTl8tCMgyUtdQV09PXTzML5PC0F",
        "4CR635//i2JmQraeBxEWXzaKY0N+4Gdf5+LIKC/gQwdWnwSX2PXv/8gK3Ni+Q8fxRcBrz2z4qMaD7hgaXpeBCkp3jdktP4GNtAYB7FXH1//5ah/DT5vrDCuh",
        "gRguEk7TMQewjwCUzNF14UL5AWQ5DIp0RwEAHooBjaGFBAUEI+L+BQ1VVQH+HD/6CIKSrK6uKazNa1qKgohWZBWNo33jfcVt0Jlru8HH67visOPBQ3MBymoE",
        "Znzw3fng27hnueF0ggnWvp/+BywhgJGUNz+eGDWHXP6v8pmZZXDE4aAHv/+KsIJjGBwBy/gEtGyrvMQLAmwKZyagVf/qLSJZ1G3mqGzL+KIKCRzsIGoaA6iO",
        "ndSZCQbERpdQK0gOPBoPvPp9q8JvUGsrllU5Yx2hLQhHAQAfBddMYl5CxHRsiFI/WxrpBtQlpa5d9BBmOe2hd4hhN5JT//+LwWrhvwCISk+J7gha8AZP7FJ4",
        "F0KDeW/7e3yoJFn0i7zcr5gG2U13n4P/4bPzYL/w1AYbZ4AIvV0zFDMj/xYjfA/FSQJwMEpf8DqfcbwKsJNnieilh6XfC+G/f2738JCIcIhubARW1d4CLLnw",
        "Tf2A2dz+9f/oNG6zYuBhhgc5Bhn2ld4Gd+gUnef5q9wWK+If/4IgyEcBABCgB8IBB6CQNkKYTB74+NB/e51vpKxIZvr4KgWA7gMmzguR+Wn0S2fRJbO0Zh+N",
        "xNGw4kL4OL8+n187mQLstlOXgEP/sFY92+zS0v+uv//7w2xQDn4ceAkAEUKwDPuId/wm/3AY2pDs8/+/yBAV3iHOfMRaCh+7ePjkpuw1r995Cvf/wV9y4iFJ",
        "vUAGW+9EeAZjU84y+BloCYMtp4ZgU1iGP/2CvIoxFyWsSsfiEPf9p09PMw8B0tMmRwEAMbEA////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////////////////////U9rT10+BHQQAyBxAAAfRafgAAAAHgAACAgAUhABO9mQAAAAEJ8AAA",
        "AAFBmhwEnLLPv/jl6sHrXmTz/ixCDvLo/xGsBNRy+OhbL1rknBRIEl/BU1pkL8qcfUQtBBZXZYtjAGZc/AHtIO2NAwPFcBuM94EHe0+C/gSDxAohASoQJoDu",
        "UvgdFJYfHL8Vz1/hI/ODDCRMPOzb/wYZfwOnzwktAYHP4MSuMzuf550/obnzH6wYa/wRfP5F/hHuS//q3gtPMkcBABMmXU48wIh7oVz6JXwKrk2Z1qvgJbiI",
        "K75wUL/ARNdet+eGxIBQuPeLDG+N2wZu58fth2IEKZOyzKw1Pyq5aWlMpVzgwov/wFCHOTwEQM/wIVJ55XirWBk1Af8BC91QA8GaxKtzxqgLX4m66vrvznes",
        "GGX4MIMPV+D4EB/v/gDL/u/I/gIg5Y9MmmPNiipYf56FJF5LloPvVAaPhqXivCEjTb1sL69/0IgprASnQK5GD4foPZn1fwl9RwEANLQA////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////////////////8F/RtHQQE6AUAAAAHA",
        "Az2AgAUhABHygf/xXEAM//wA7jElhPU7Ur5xnf/7eP/n/RKSJN61k8cRVWJVPO3tddXW/dy9Tt30P/Tbvs2Ap5556TSgJY8lMSce/n5XkkXeIY3ABEMizNgZ",
        "mWjSBC4Bd0BqKq5oe+i4GWQAvLKotdf/8VxADR/8AOoxERJEIskmfMzO//w/j/8/9qXVskvnVTNKSgkzBAywMDP5zX6h+yfRb/fcxisGBgwYkgVpqRu1rEcB",
        "ARtdFhWpLoSQvcVrZAS3d1RbvXUFmosrbJsBdilB7sLnQlEKigAbKvj/8VxADF/8AOoxEPRHCTzObnqt63//F+n/l/7RDVKIvviTm6CU0jlxjRkK1Emfxvek",
        "O+gMjuiiEUmIQjuxYggUSHpAkkIxDjEB1b8gwQhwQNWNFa1Ogat3eXhLX2Z4CUzRt//xXEAMv/wA7DERMjJ6lISl/NVm//T+n/2/2tVyGWSblqsG7JplzTel",
        "+cj6p5V/RwEBHEJCWug1BjUUUdC1igQGMs1C1mWsHdY30HXXqmQ7JuoCSBSwhJWKzCjBHrlV6mMOc1IpUJ5YuP/xXEALv/wA7DEJElJgpba93PM//D9P/b/r",
        "pM0pKax37TO7sNOVcSiiy6PGn86/K79jgkceMWXZCggSMqCCEcURSIfFUyTq8lbS5i98z245fnovxBIbQhcJUWyT4P/xXEAM3/wA6DEQ9lKzDxmPf/6e//2/",
        "zKkrjchDx1dc9YA+2ERHAQEdpYQlElGUQm3FDOAHgCF7duoY3Q86ZlC6GBbDPu+ZrQGGE1rFLX5GMBy6ipWOYMeAQu/6XMOJCO2wy0LaCUiQcOD/8VxADP/8",
        "APAxCNZiYaky/GN8//h6//H9SJM1l1rKrVXu8Gxo+zZOKyQokLeDc3jbP2tKMDJ5551TznhnQ+/MedhKHSEtCy93ZOuSoSV5lYu2jK9UtuUMx1cn+gVjPV0G",
        "OS0Y2vn4//FcQA6//AE+MQBOSzE5UEcBAT5SAP//////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////n9d8Z4//Dv/8+LvIuMvLitZYB8Tjrq2T29Tl608PrcpHnH0TcZmKS893pYkJeS8zvQyRIekxzAIDydK7v2ulCrEe69R0",
        "sImVWUgUYq9zqtY3CJP6crnqpU4szEqsjcZQuFceR0EANQcQAAIF7n4AAAAB4AAAgIAFIQAVA+kAAAABCfAAAAABQZoqASc28qsI94+O/ny/kgeA9OPnyRks",
        "9wSeff/F4/z3Mw7fv/hjdnGAczAzrCPcIaKWME1+wiR2wNX54eHCUni3k2A7mWohFoyIMDhYQBKHdNq8DpDljkA4fHAyVvHAyPpV8JHsXwi1geEatUyr4Ez4",
        "Ol7CHB48Vy1/wcL7CWSAJAoIABRAFg25a8DxtLA8ZLmowGiTzlBHAQAWraCJmXC7L4NXLj1gIhCRH4jfgypfg4Olw3uEum/wsDDwQAwO3/iZnwTdPrkiQQpo",
        "Q7EAJ1k0m4LUUsLVui8OMf7PolfMxjbAk/SOt/s/8HB6/hD8EjcV+d6b+rPjVNNH04ahQIoQmfECZ/wgtCtdPnAmf58QV+xAQN88Df2Uq4b64UBDAgHgEkGA",
        "lKbXef/wIGIX4OfdU4+Ds9fw06bDV/qWuBABg2+ev/Af9cej7v5rbIRle75/H0cBADd/AP//////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8oi",
        "LYt4VyzyZwYqXH8CguBQEsTMkuXxJMlFS/wdHEqg+/mFG39j2ic8CK8+ybJ1JwY8DEApcbrUR0EAOAcQAAIXgn4AAAAB4AAAgIAFIQAVSjkAAAABCfAAAAAB",
        "QZo7ATcvasRAR5UJa1fFxWCDCFf9+P4SFihQPmwI1lSJ8KXxgAyvfRA7gza8HZ5qBoOMYxo0KDRx00ZzRiazgzd88J4Yvt+cGCZfwibn0wOY2vAgA+PzptD3",
        "3+EKPxIAcIAVFDClS/gEvvhP/oNCdperz+HBvDj1eACNv+V5/gw+HlTquDAGwPVY7AxT8lXEO8M9qan5H7hHAQAZa7Hb/hFDjxMgguzl3wPIrn3AKOeA6A75",
        "vGm+YfwJBYKwyRCZ4gTPH7YReQHJYhM7iBM/wXLYVhAGWrUuC/+EugbgMP7Pi/w3sU7956A38OzZvgw1+fwun8DzFL/g0OULmQXG0VejinIPzVRzCG4NmDdN",
        "84Ez8v/+EVBAnSIJIEc1MHQRn/iCeEQL3gWuf/VKtqekDwiddc+l679X/Vz86AXYt8ID2Hj+CVgZcJmeeTPr4V/PACAEF0cBADqBAP//////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////9L4f2n/XPBP+cPcF/y66bxPOl85Zsfl6rp4CQgUN+eAsJTUSTPEkzwh0B0STPEkz2eCHrm+oR0EAOwcQAAIpFn4A",
        "AAAB4AAAgIAFIQAVkIkAAAABCfAAAAABQZpJAFHN2fG/kgp/UwmEIesCCEPU4Z8HGPqBRAYEAiG0ULwWnTlgL8fMLhgkB4YBcaDJS/g1OX8Qfrg6+D5Z+4Co",
        "UYp4MEvfn8Bv4uSifweHqHdN8NNN8g/lEA/CzL4NuXH9KsmZflbl8e8KbID7wkfhEh2xwrZ8EAMNPAUGrfr6/PVs+/wjpEASZV8GJXCs7n+IkH9AR/hHAQAc",
        "CItpd5uAoMY6YS0vHu2BIAmLz7/+d5h/8T2sHo4+NCH4OM/1hsCJnYT61jnwNPwar13AUC0YKtvBcPVBl4+FHDcFAlBH7Y/cwQ36Y4TIDL/vO3rzwCWCL2P/",
        "AogvDVVwMDHA/RYsQAmcd4sL/DgFTEIGfQGDn6tzgwTryhELQ79VqxafgUMnv/+/z5Cf/yJ2m+/DV3wP0wTytN/Y96/xvo/r+u7XGe686IJh+wjD0qMPJvEd",
        "j/45N0cBAD2qAP//////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////+I",
        "7J56/W94/v9R318sR0EAPgcQAAI6qn4AAAAB4AAAgIAFIQAV1tkAAAABCfAAAAABQZpZQFXDhPyR8I8d/PmVe6vdeeAiAfgQrVc4E1H3PBhGeeCG5tFv+Ep4",
        "Qoh63jeP8GC//P7/Ot8dexFgTO/gw8DN8PAi+C5R3fBUp1YuZMI5oKQDCrz18IPHX/EcgvhTNBExpH8A4Sk+KL/wZLl6Bhrg+dWklga8ZOGPC9hCZsnBh8GH",
        "wXLEYqNdMQlY92wlEbxS/l/vB9NHAQA/PwD//////////////////////////////////////////////////////////////////////////////////8AU",
        "AXFvgNu0tSQFjJesWLf/Hs0ToKm/wIdZTe/W/543CSn8/inH8bRSITLeIEyIEz15/YRjr/48GaseDHZ4Ie+r0HkBHdLldDQMHWegE/A9ruTHfzwAoMrv/EQ/",
        "nZc91LAS0p/EdC2CjWd5DsFf5wTe+C6+lm5fqEdBAT8BQAAAAcADN4CABSEAE/e7//FcQAs//ADyMQkSRDDBrMzt4z/4/T/8v9MuoXiyduK164BGXA/qf1nz",
        "5D80+W3/ecxgZevDGyz3hjYzejSPljeht5Gy6FsUSgZr3dshc5Oy9BYOwKFNl+D/8VxAD3/8AT4xACyLGSlY//+v2rWfx/r8//P+IqJJkpK4c9VKABj3+PUc",
        "LGeXj/5bi/h/3yCXiKhYR/v98v3p5RXPDTd3SoexZitRnVaERwEBECBaqS2KgNwisfdya3Ge8ogJGTMxvc664mHM1+7pZrtVfGkVqosi4nCpmWN8//FcQAt/",
        "/ADsMREqRDi5ieM575//i+f/L/76il3zplyvXxJ+fiAWkmmwSTTJHT7XISD0ySaZIuZawzBJWiaIxdvKoi28qIlBe8Eea/ubItsa2Fi9paCSRXT24P/xXEAL",
        "f/wA8DEJLkJgpa7lc8+Of/2+3/f/7XN9VN9YuZXjzrPXUDEuRVRRRROF27ZHAQERiRFFF3RF3ckPxRIIIKGrECeVwkWfKoqgM2eOqC26OFPXdm3jERRBKtC3",
        "//FcQAv//ADuMREuMji9Wuec55z/8P0/9f/KNVKm5xz1tz5X9vahUthhhhSpdcv4fkPYSE7rd3N/SA2uhdC3SNorTn01nD7o0qJSGHBx6Op1tbofDh+Iykbf",
        "fMAlw4//8VxADP/8AOoxERZCcaFSfNb3v/+1P/X/OSlx16vVHOjLApYDcqHXh2tkLeBzfkcBARKdD1GdLBvZ8tny2QgFUFH9ROgKRaI/ZvdUdR8FIdGrMe6x",
        "8WwWjVSWoaGtGHhUpCVbQqamSSOrwP/xXEAMH/wA8DEI1mGy1et8c+v/T5//P+cuhNVeSteNR35BdKfNjzJCye2U5DWOWGWKIjQvr169c9cpTnrmnr+HLMdI",
        "To9JRasC0YHgv0QnOebwyGu4ZTc5VOLiZfjfgP/xXEAP//wBPjEARksyDJiCcr//x+a879//T3//L61WRwEBM1gA////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////1rxAtWpWB96S1lNyN+AKckBJga1E93aVrQGk",
        "L37bxgziiuqedqc6qmp2inXzL6ugUHP1AGB5wqhSTfrFBlBNmpEqGRna2bfr792njtye6pnqXbHYymLxykqkWpONNvBHQQAwBxAAAkw+fgAAAAHgAACAgAUh",
        "ABcdKQAAAAEJ8AAAAAFBmmmAVcaM4CISkwhi+PeB8wpsuLfCQAbYR/CQWOFDUmCUlXwQNeYCB72He8b3/beDBXiTv+e3+Ej88F3LnhhhZh/gLPF3R8ziATwr",
        "wqeKuS5J0/wYL/9c8RwYaz/4OP1ai/+DCfgK0fyw/hqfQGP/Ei/9RRfCEnns/wTea3rPEFL7Yqv6zwwHjfEOie/7AsAIA+ADjCd+cEcBADEbAP//////////",
        "////////////////////////a/f265/ia4qh/AOFbUkOB5Fc8fn4oYVEjw4dM7nycGCsfBgs/KBinjTh4CDVNv8AZf934vPAomxPYq/k9uv87iEvfgp/fywG",
        "TiIL/CG68a+iD49gyiWgqb0+Eh0t+r7rgw/PgBgoJ4DrYrKQSLjsP6nazsEuf3/Rfg5/7dB5OZP7/6vr8RBLKd8/R+X6+6+uUfBQblgSr5dm0v1AR0EAMgcQ",
        "AAJd0n4AAAAB4AAAgIAFIQAXY3kAAAABCfAAAAABQZp5wFXCAR4HMYGdYR7hDRSxhI/CYWY3zwPJw4TS58fwwoeBIApE94HmK4Vjl/HqbgYUBhoLIR0FDU3G",
        "XzsqDP/4ODm3/loOvT/ECHx70Az08uir2D4BAK58HC9+dhjjgfcTr8AxVWb50ER3GFPENRI7jLes/Bwpy/Xvgyl87AO8Can3P8Gx6/Js/QaAwdG9a3yeyL/1",
        "waFHAQAT8QEf8Dpnc4qqdF4OD1/Ao3gDqTuJf+DSBYPu/jLcHceSoOhefhCPYf4QqBqF7+GzT/3PXSNyRNN6w+K5oHGwilEWhAE6V8SBYOAWPMAjwFHJgWgQ",
        "LxsI9w0yx2FD5Mut+B0hyx4GZl/wKIcgNPk1EpNkP+z8C1xEF8t5wXO/lD4fnqzQP/cHN/z+PyrgSoJRHb4ThJ5x2/Akc8Ecl3XnDyVfjU5TX1+eH+eAizhg",
        "Bb8HE6bk5DwzL0cBADSrAP//////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////1+fqT5OU/+g8kk+oR0EANQcQAAJvZn4AAAAB4AAAgIAFIQAXqckAAAABCfAAAAABQZqIgBZxa8bPQD/wPfc4R/15zAcMcDA1sSdFC8Hj0UF+DBY8",
        "Sd+vrUqMs+eJadMIj67/zwS5DU5L5yU/VXaa+ElgYBwpGDNLr+Gu0/H8DA/AcAw/EDooLwKopYFhfgwVOhHBh47Xr3hCogpPc8HQjKVoeBq3l3+fU6cRy+eA",
        "d4LPJ8fwo+zio8i/v5AYeDIIq/j6tc4/4KJHAQA2PwD/////////////////////////////////////////////////////////////////////////////",
        "/////3wEx9wEdUgSPkvRTwEYegO/PX7P5ODD4MPgwW+P1DpTrj3yWz+EeEkRvnd/4QVjsCYBQxCBnY9gqoBM0OB5iufYCQ0d7+5vmzwEXhs0/1lwfynfquvr",
        "vgwqaD9bWPfSdesh4Zvzh5fw0zpxJfX3Nr3NxX19z8X9QEdBADcHEAACgPp+AAAAAeAAAICABSEAF/AZAAAAAQnwAAAAAUGamJAWcd54HAOOEBOU34PHA9dg",
        "bAEArdwkfkuE788YXiD/J/Bt8Hyxz7PD41UyZ/88JDda2eED39+88EYQmQv4Cix4Pe/bcIRExf/AYFXy/8HUCB3AUCo2vr6vXL9Q1CQCDJ5Df+eA0Bv24B1/",
        "Jcnm//IP6Aj/AIjtku1uAolr4PFywhNDjG6KLCcfD/w8DCr1SJRHWcGBRwEAOFoA////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////////////////pF7GAyrtULq+/rCQMPGfnPr+EvDf5/WL9Tpz/UCN19dE+ev9chASkLkz8",
        "AO+VTuff1+v+I8/nghs8/XfBjf19HfiPiNAmCUR1ngn76uDWT6P4jzv8H2/4r5DvGfVHQQE0AUAAAAHAAxqAgAUhABX89f/xXEALn/wA8DELQoaj9JnPz//b",
        "9//f/7cVK1msXl5fjzU8fGBUkmlPf+/29I2YGEn7eT33OMcxIY9zEgOXENIeeM/j3IZJTML+2PaSSds9k9dZiRIpOuVI2zjw//FcQAv//ADuMREuMki1rxfO",
        "c73/+H7f+//fQl5xylyu+Jfv0CWDDAMDEgZrx/B8l3shDpoo6Y6FmaXX0dIPwjdsKP2ija8aW/BQZkcBARVOMScdDD+0T7KKEZYcCZaNGvfw//FcQAwf/ADu",
        "MQggGVFISLz3bk//tfb/2/3uSNZeSqXvUrvgKomJhExOzb1nXz7X9+j6WAyIoooonIokckd3IXTXB1/ghBXgkEEBARIYI17CJMjiGRSUknP3jOEBUD6c//Fc",
        "QAu//ADqMREyMbKnO95O//2/P/n/zq93oyXuzx5X79UAxKhwmmS/Kf6THz3449gkha2zZ647PXG/SMehl3ZGdK0YRwEBFtkb2JbbdxdGGEZILXnSPuG0NGyQ",
        "oWvbgP/xXEAM3/wA7jEI9lI5vayfLm9//t6/9/8WSusZmousl4BD/DYh/5IUyWBF8Zft0Pj50sDH+Xyi2ZQNilH41L1aySC16557HLx2yTYGx/yWnDXKoxNZ",
        "uLc3Syvy4VgovaTgvLOnwP/xXEAMv/wA7jEREkJppcd+ftvK7/9P2/9f+6Sr1uVe9K3pN3QiiT/MRN0T9J1upfzvyyu4Anud57lHAQEX23kseWTd4xVAsUBj",
        "jEo54NVBLQUynMVjTRXrGdoFuttB9gKyhyZxLltGnP/xXEAO3/wBPjEASEsxOVD//v+d9b8f/h3/+fxkVXGqzfF1Ki6mB/2168jUHucPenB9YnU8589b7I2n",
        "ZPPP6zzqnOJp9kM+BwgHAX6rWqu3fUKbVdF5/BrRUTNtrqGBhWid3HfUS64X+iW64LrQqJipJtKiGY7/8VxACz/8APAxCQ5SQLVcd81338//HUcBATh1AP//",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////b/rV5JdJfK530e/sEiXMUvPPLcf41eqgFvPd+ljzCueHfIzHvghmVskgnVNOoZqwh4NcmrTLqIfmLEU9ACmz8+",
        "R0EAOQcQAAKSjn4AAAAB4AAAgIAFIQAZNmkAAAABCfAAAAABQZqooBZxnnhKm8FzUvhDiTQCOKaghdh3X5zBg4sJE5BSxb5jOhYLc/hBVBYKA1MizNwnVHPq",
        "+oUOUNcBZYtcphfePdHxGwYeB+N5gXL2/g4Xvo6yu7go/T8fwwa39j8ryVfUDMt9r56nWD2BHGCkraPhDhWZAVYoNIt/5d8vnYGBrOIHRQX9fAkKVvA4BAMo",
        "Vn+KEMFArhFHAQA6DAD//////////////x/5P1J/X1l/8/nHzoCrCBZn/wZKX4HY8Du+Kj0r6j/eQf+EpPp45wURS48GHwYLXwaLX618vQcBh4XDXilRPpf8",
        "8BH8YucM0iT0q/z9K/x1yh5fV5Ir3Xy2eFcXi4vF4gmjoSWDhY/4qBvo7d8HGIQLaF/dn5oqBT6g+7++/sfBZAOFbuIWOIFiPeA0JasTY4ksSiIJZfr7OudZ",
        "/OHqIv4txV39fEiIf5eT6kdBADsHEAACpCJ+AAAAAeAAAICABSEAGXy5AAAAAQnwAAAAAUGauLAWcTJ/npl/CR+bgKBQPv9AKM5g6HYnqli/+eFDg6WWTW//",
        "qEO3+AhjrERSyZ4AoDcFPATi3n4MNE6/Bl6r6ifv/qIyfnh0WRQWPeCh/1L/upBZPkX/VA2o/gbsDtcJwGWBDnWMKWZdkCCqBhy+2ff3nhgA8NYh3+NTHVGm",
        "Cw/qB36Xz4lX4nstQMCpVr7AoAfj2/wBRwEAPFAA////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////5f9354KlrU//N4IuIQL/CGtiUDCMeEp8gm/Ca95uP8vBjcTyHgn3/WzcXB/L85/O8R9xWgTcz0LnnR159fZ4J+uuDWb7vOC",
        "YgkH3E94Q+DgbVzauzwT53sIwTRlATvV8vzngnzvN9RHQQA9BxAAArW2fgAAAAHgAACAgAUhABnDCQAAAAEJ8AAAAAFBmsjAF3EX+AsqlFqwKcKgclEUngYw",
        "dLHHg3PBwEqAHFr+T6/9Qb3edAugPj4IZdjM8EydY8CCvxm58oOl94IAYd2pEC3J7b/gTaiUlSynnTG///nhs7Ihz+T3v/PD3DXRf1N/BXyvSy/POo+Krrw5",
        "1VCQsf8DzFLHQRmvA2TzIBv4PLfzxoFcut0/+oZS2vg2UieBQCKgOkcBAD4qAP//////////////////////////////////////////////////////8DiE",
        "OK6i1/P4lr8kT6xiBX6sEAMPgu31B8gWYz4POfmqCY9C6fwbXfwSHoDvoWkv08vXEfghx32xPz8gN/FVhBcXbbz6fTj1NgloQCdZNJuC1CditVsv16mm54Rx",
        "ENv84aJJJCSERhEYS8H830P6Eq5n8DjCuQ7BXI/k4zabeS5ZLlzrnea+X6rktYqAR0EBOQFAAAABwAMugIAFIQAZAi3/8VxADP/8APAxERZCaaWtz1XLf/08",
        "f9/+blSuOdYnHN+uLrNBleGBl4MSa8RsAXJ9pR5JLACX69H6onV0/oV9VGBgZppZzrnB+paqsaXabyo5iOsVtHErYbVkPs0O3MK9Lm3K0M3A//FcQAxf/ADu",
        "MREyMjm9L7zeV6/8fp/8/54yK88ytc6VVpuwujkUtVGB/IwOfxf1p+ZbAyO7lEjkRIInP2hCxe9HAQEaee7Lxvxw1qE59W1ft74I7I2cF4IT1cdk/MmC8aAL",
        "7Ovw//FcQAtf/ADsMQkSQbL7d5zk//tev/X/a101V4kqeOpXPmgy+ihdFFG3Rdb6g/gSQbNmyN7NlrRj0R2Rta1LulbRWtG1pgzNG2LhaNypSCTEXlmyV2XK",
        "UT8v//FcQAx//ADwMRD2UZmNxmvnDv/+3v/z/zYuVu7y6vviKvBhlZ82rygyVqSu4IN8eLvtcARpp9GrVWtXoUcBARsGq6sCBvUlmxJb1K2pcw6o866aM3Kv",
        "MlbjoXf2GvStO8IJ64TtTv/xXEAMX/wA7jERFkJhqa549+Z3X/9yf+X+66avnrmpqnv7TGA0u7y1Ld1zrlFCQcv6RFegwBC695/S+C9N8rjG1jnzlukgOE49",
        "6ENHVF3EKoTi07RwFifFq8DwqIogmFuA//FcQAzf/ADqMRD2UXqdXHfjet9//t+n/7v5qSpNbl1VWIQDM+dDr179khUmcKDWRwEBHFHZuFimBhUpvvvvde+D",
        "fRvaG/RTf1e2l0K+W5RoI+MTnSEQBVCmQYtalUPdhiYBAEAyJ1E54P/xXEANP/wA7jEQ9lJxoXrPtnPHj/68//b96iXWTTOKrLlZYJaP/7F23brJTZQsLj7u",
        "Za2QGgrveeeeS49p5XsZIA4bzZFTpcDxNxOjGReE5nMwatymJFCFTsNXdy71EJa8Lw1xC8tXgP/xXEAN//wA7DEQ9lQ5vayfatzn/9vf/89HAQE9YQD/////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///vqrlSpJur48ausmDMQWLWDBiNIjhAZQ41ZzKVXEDIYMDLz5jEgyskPFqu2ktt27J21ropdtvIT1rxot7vRq9FS5zma2TPpStusVMtfx+HRgiRkGRLgEdB",
        "AD8HEAACx0p+AAAAAeAAAICABSEAGwlZAAAAAQnwAAAAAUGa2NAXcsWXfBh/+v+oePCV9i3/seBRPCFQ4BXL8QO/vOgu53D4bH+YdPiBnX8GhW4Ulcz83qIp",
        "P1GlMIbgcIUIHGFXLLGOdrJWoBLd+edSFVZ/7zzr1OY45f8UC9R3fBeusfyMa+DJS+fa+DBX1eA/p5kF0/gwRS/wNE8S0Red0m8ILIvxb/54HAMO4jv8+olJ",
        "zfUDR10XRwEAMCQA////////////////////////////////////////////////hHH6gzQPRyU4a0CDrd12P4M7j4NTl8Yl/wh6BgEo3waRy/uAmOK5fu4E",
        "LE8nxH2fl+h+VcCUglJ2+DypwktW2/4heaBqWgBfyHYI/0HioKm39C39i3vnXeBZ9/iIIb7QJpP+eG1Auvw/7f0d85AQvEIuLY6SSQ8IyX39ecEwC34OunCC",
        "4kQti3/4Mf1ACAERfcBHQQAxBxAAAtjefgAAAAHgAACAgAUhABtPqQAAAAEJ8AAAAAFBmujgF3Or4CgUAUy3AUCtyAcEqKHZS4TCa1ygXwmdFf4jv+B/PCCv",
        "aIWZfhD8PiP8OXvQDP7GB1q4Xz6Vfpl/1G0/UZT9QOZQk+Sb4MtYXerZPZP/yeUv/8udgMA3iXfyD50dS81/+eOEojonFun8JahiCCoON0bcxOH+DnHvi4EP",
        "uefhE3PMAXCfw6F8nT+bPBff4SPyvkcBADIDAP//DZbnNqBsnNrFz/P9fXiILfh5Auj7/WO7zlAJYGTKl/b8PiVfwFDU6ADnAZs9Ad8CcW3PP+Y8EvXcd4zt",
        "JE8noMFRUzwv3y/f1g6nDyT4U3Mk3PwK3wMngxAxUeH+++Dc4JioQmvwphTpr6v+pUFTb+jviYIc/nejz99cP8ZnBMZAwy+8SmhVelD/AAGPfkJ0tu8br39H",
        "fO9HeaWAou/k7+oiAtcWvs649TYDXCmxV92y/J9QR0EAMwcQAALqcn4AAAAB4AAAgIAFIQAblfkAAAABCfAAAAABQZr48Bhzepk+DJfYRwReqB1gLMIRuTkO",
        "WP/gLKoiSAF4HMPrdyAQZ4B8Ztb9DYZFd5PV/0FkQmvBUr/qMp+o83yKMU+CjCCwnboGp+JS9Pp/h3J+/x2pE5M8Nhqy8Oxx4S/n86ED2piXBPVPfCPJAvav",
        "i09PHqo0UBgQwvTaw9ShW5eM8R5P6/gZlQOOdfBgrnPnoHHfhL9HAQA0HwD////////////////////////////////////////0v5/EIvy3+IQK/gwQMERR",
        "8KKIJqG88MBwsWyywp6/fk8UKYoBgfQRPCkZvEAJn4KLSn4MVP6n4qO7l7rx/AOEpPvxJYk9P8Cx6GcA4GWq8LgVvw3e8JaTin8l8ld4MPhjYhAhfgxyS/JH",
        "nDy/k0YlP7/wGBsTD+/5d146HN3+d7P53zz99xcBEXfZ3zviPEefzvn+u4vv6kdBADUHEAAC/AZ+AAAAAeAAAICABSEAG9xJAAAAAQnwAAAAAUGbAAw5PUy+",
        "O1Mr88D8Ux3v+4F5UyoT4F88Smh2P8Nx/QnwY8R8fBFXDOT+L/B7XmHFf/55UIF1+AhGpjfCKzIR16afoBFVi/Uqc2olJ+o1Tfx/w+rGX/XPX9wl9H174Lz0",
        "PP+aok74YPAiubzX+vzsDg5nCNCHUzjP8Xn/+AWssbfP7zvWAqEp0wguvpfPyyQF5ydcDEdCRwEANkEA////////////////////////////////////////",
        "/////////////////////////////////////////////y0Ho8Y6fHkpDcNMDXxbn3g2BeeEs+tgm1QVf8IKbjZCsRQ9UssvqIBM+oGFX61Y4jja1frVOtZ9",
        "+PPRU9PR4f+DPOudfgxQc7vixEP9d18/L5w8mX48Y53x5EWkQt/5fIeCPruvieaflP9d1524s/19fX153ipHQQE+AUAAAAHAAySAgAUhABsHZ//xXEALn/wA",
        "7DERMkI4uVM7zd+v/w9/+v/XSGmVrfFO+qnjigeqn8VSgf9D+Zvy/+/YeWgkSY93dIkseUnJNLGWBwpmkn6YZ4OqVYSHghhhzSneCUyv6igQAgK8//FcQAyf",
        "/ADoMREWQmGpVX9sc6//t/b/7f5rSK4c8YccrqNgeGnppppvSV2wEeZJD/BeUBCiiihZo6FxmF6o0ha641r3CycbWpK08kcBAR9Bp/pLwicCMZTva200dbF/",
        "a4dZxCSxcS7/8VxAC//8AOwxERZCeJ1M8R4f+n5/7/9Uu2Srqusr3+Fb4oB2dmOKLoSI6mL6q7PFyWUAGREUSIoYkRZSEkQ2IYjuEyCpCkOIdESifF6928he",
        "ZEZs9H7ka65yUSLXv//xXEAO//wBPjEASEsxOVD//z6q78f/t8/+3+V0ay6y5UlLAcTCEpksGp2DZ5KyCDHg1Lxw8UENHn9Pp9B9NfOPRwEBED07jUQXtrwB",
        "lwPdqDMNbrWlKYakqfs7I1TeVmpIWKROcVu6jG4uMH9JY6irkIwrRExJrRjlwP/xXEAMf/wA6jEI9lKJlUeOWev/7L/8f1SVxi2u+NyoxdDhk1bDz7BUQqkD",
        "e6TZ9znRgYfmnVzH2KE6pzzKO9CdU81WgH4s4GO6o4JSAz6omE5Sa1ZA1r8+XmCDtqsZItTJwP/xXEALn/wA8DEI7lJJtRf2dzx//Z9//z/2TW3Ga5RHAQER",
        "vNe/VueMDGc+l556t9dLy+SuihTzzzz2KUvPCRjzE/kzzQaOxZQonPgmKzim5KNFL3cPJTevBBRe9UgnwP/xXEAMf/wA6jERFkJgqY6/Sqz1/9Pf/9/3qSrk",
        "51rcrXOlePIRjF/XL14M+mDqARxYJtElWxA9p+qefqODiefpMYwwr8DnaVaozB2vbKbLPcyeCp+Borm3lDgLF1YgO34T4P/xXEAMn/wA7jERNjJgqXfjmuZ8",
        "/9vz/0cBATJrAP//////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////j/Osia31ukX79db9eQyH/YQO0DF/M9Zhn/NRnjxwsDD93MQiId12KO4k4kkXOconkFVOCday1eAYT8pNHPlFx",
        "ndm3jERRVnNIQ9PAR0EANwcQAAMNmn4AAAAB4AAAgIAFIQAdIpkAAAABCfAAAAABQZsQDLr1Sr6pV9a+lBFOrUyaN4O9zwY6nufxMGMnnBhIlj+ETQ2FSHcf",
        "huteQMOPwCJ1L49vv9r4RXTL8uir+fEQUvz6uXUic+tda6+Jy//Cp4DbgPfUf8KVcS/wf/xGegcAMH/FMvxIRR6Bu/xJ3J+b//nofvsiBFVxZ9zZ6B3/MK3t",
        "lHh8/NwIFerHUDafwrn8GDd4/SBHAQA4SgD/////////////////////////////////////////////////////////////////////////////////////",
        "////////////kLqEQ8/nDv5g+fGtDfv/g7+Dvn4n8QgY15wXAEsGpy//hm/PSoMaZNuP9y/H+f5+c8P8/y/5w8o/KUzn+5Pk+T5Oc7BHj2CQDFPg0XYQgQuf",
        "hh7Ky/vBhiJ89fS33fKd7O8TNySfJ8nyfJxH1EdBADkHEAADHy5+AAAAAeAAAICABSEAHWjpAAAAAQnwAAAAAUGbIAy/z0q/AIntaHGwV+elXzaxwfs8069m",
        "tSLwTWvUFqfqVTn+J/hH/+bzlQOLvf69vHgLb8FitzZ6deWvqtbUyrAiAUVZ8EKt8P/BD3AUB0YiKPwD3z5L/nlEKRn/Em5Z/n5XX3mn83jnS+N9uASc8dkJ",
        "rT/+p4AQiREKriq+fDnVQMAacAHEHRQv8Rr3EcTXyeIQMcnvRwEAOkUA////////////////////////////////////////////////////////////////",
        "///////////////////////////+5wUBWmAuKC/4QqFM1wbOX/+FAX1wYqlVG+rxuC3+tAPXgxAvK5JNq3wZ83xHNfV6lQVPq/kmz2x25W3INu5K3cydTc/n",
        "iWhAJVpE3ATZL+GKZ5s/IS6/T+8TyHfm+b5ufgqPX/e9qo0/z+IQf5+cQslHQQA7BxAAAzDCfgAAAAHgAACAgAUhAB2vOQAAAAEJ8AAAAAFBmzAMP888LMfg",
        "EvtcsCbS8zC/56Bxx+AWr10H19X16lShP4Q/+EalTx+n4/2Ff+T8xv89Ivp396/wgtIvtavWL9QXua1JfBysM8PgQce3X8e7iIK+4CAOC4jEWHwNZY9tfn6c",
        "PPYRia52/W2/z++bCFyx+CbP0pE8CgGFTqX/9W14LKnRF9e0/nlRl/HehHgkCCBQMSdGv0cBADwqAP//////////////////////////////////////////",
        "////////////g2cv8+rOJ4q/J7v/q/6nTfhyp0+IP/409FRo/gwGH5Ug1nf/J8+C/+sXwd495VcCH3PPz1ib6sPeX/POk+jMb/+eImsRC3/HuA6kbUAcBwIB",
        "jmDF8T+zjTFsW/R7/OjNT8kT4j4vv7j4NM78d8vJE/FfFZ6xxbIfiO/qP4iJ+K1s4j4ns7BPFnXEcvzwR0AAEgAAsA0AAcEAAAAB8AAqsQSy////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////9HUAASAAKwFwABwQAA4QDwABvhAPAA",
        "D+EB8AAvRLmb////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////0dBAD0HUAADQlZ+AAAA",
        "AeAAAICABSEAHfWJAAAAAQnwAAAAAWdCwAymEQQE7ARAAAADAEAAAAUDxQqEYAAAAAFoyEIyyAAAAAFliIICb8O6hBCSmQv82Unbp0w3SHLUoQwAUINPCotG",
        "MAmARrSMfHJI4Zym3F0RWWKoIwXuSJ0teJ4VS3aVcymmRDKaaaw5i0GnYqXGdxvnEDrN84xUxExVuicSlQzsCI6liI5qjUnmQy0mwR0FJmWkSMspRwEAHgYS",
        "bQ39ERWUg+W8KVLBboTFRVYNkzRkZsiNBE7siMt1+Gzh6ykp7EyJmMaXR5bwHfeZO12q+mQBXVmTtlHroYL1/3uGw/+ZXxHEdxfkqDoyP5O8Jeu/GRsnU6WC",
        "Z/E4LpgP8pX+6mqyrq6rKjsHQjUAmYsEPlzFS5jw0U1WC6Y0Dzp+GymIofYI33viBH8BNb4fBkeufcxPC7lUT4oAAg6xwABBojgAFb4yGAB5ebC+BhxYHj1R",
        "JYtHAQAfiAWFCS9DDoZICNrsFF3Cz8GSuARruHY5m10I+wEQqvRkMB0qCThEYwtawPGS5gQqOxe+brmMOhkeAhaxR5CBBON/LQJieHRdHSGIIhQAev1r8cDB",
        "wLX3ofSR63G5i9IE4MLX67+LVaBzP6fn0e45LQ4Z0LVxHVrbv/hiIPX/9aoxsjieNcCj+ll1uhhZykv956dODKWXQmL09HQBRd1eRxfMwXfzP/S8fT/w4DE3",
        "9agiguYoZPZ1r0cBABBnnAsDLD50BmOBgAoPH2WZuDxyVnyxvAVm5v+n5MzyT/KRkAT/Cmc2AbmJa+J6J9q0ryNWypNso2QT41hIhBK65m/pfKOOtC7QudiS",
        "8RDYplQQKuqeGIYBqXl//4xQGBolPEmaozcv864oXRg7TP7f+WEoItqsCLtou1LQJgWo+y7IZ/51aGVf+P+HN9qsDgagU6buuwPIUvCzc/xwguCwVQO4ELtl",
        "4MGV76wVwCtl/Rln44hH/QaLRwEAEUvuFNAwDAgEp02u0UXMHi4D+F1n+C6/AOCooGAtQpmLbeI6HJ6l+8/FxQcZYBEAXCmWeEzwanLOBMimPUAUBuAjzLHf",
        "gJHRw7xagJWtPwAkImQ85M/jwZnF4fZYbggqBZvtXX+QvZVv+Kd5Vr2hNCkG6WbFDHGtZmMDoUzydhdbTrr4f/sFYUgwSQcs0K7mS7mP4QfwnQlWhdAmD7LW",
        "9v/4STIBYCIWk+8K1oLlx/wf/FODzwGEJAdHAQASADQ+urgkS74U94zGmpWA3hdlnAmeDJSzwmRmoMAQUAsQLzVAJvpwu/4CPNY7xSZuDhyBAwQ7sERXY/wv",
        "iq//t4HKMD5hM3bb/AJX0WLuTRTYJfXOChdwSvLQRkDzFLwCqlPlmZy0wU1dddPT1LT0y1zNigAHo3ElaxaBiHaYJcQFvhX2fEAsRALAzgwgjSMnWCHHLH/h",
        "nFr/+ngYXHZD94HgEWmcLufRVgQ+354Zzg4XXLgzIHSOX0cBABPgDbN655hKWFqCvP1r/wgdShCJxB3gIBOoxP1C7c8Md7//wxhgOsDH0vVVV/PxnJZ9ddMt",
        "PUFdPT1LTdczDE1GQ4bBLQgE6yaMS8CssJApUL7jD/+wVgzXjWICmWC8MHBeHxrBkMoA+cKjc6T3pDASmrceKU/BgY4gie8Eazhnj+I7i+F2Uy51gi+2en11",
        "0yxVQJUBKUb6csRvpwsCngXQF0u7PsV3Z5Yplpgprp64WYKgYr3/7fECRwEANAEAqA5jwploM7yaCOlYGOkIMgwBze/T6rJ8zQ73CddiVTqBjTQk0IBKsmjH",
        "+Q6R1TC1dAp4jIJaoV+1mcZxltWvMw/9SH1108VBJEuJeO94HU+4rgOgOqO+Hpd9MI0wrXT1xsFwzUeDJvx+WuWTJkfTVPIKYJxQGIik/4Q/YhD9gbBIkL4G",
        "FnoM+9mKvLciTst++H/7BWPc36/5zTD9dddPN+Sunp66euLYJgHU0mG3/d12tPTBLXhHQQEzAUAAAAHAAyyAgAUhAB0Mof/xXEANP/wA6jEIQBQllJapESc8",
        "7ut//X3/9v8cFSRdZBIIL5JsJtOH1hbghW3JlEP3qvKAl4fqijp6Vg1CzNHG8fU5msL2FoEoJASrVCPLCIogWKvUtiiLTetQ2b+mytmz5wKc3dyhfv/xXEAL",
        "X/wA7DERNjGyZPsxv/6ft/9v9LlXnFTI43N3e+fOw1cBpcZZfR/NF3tV4fyrgCNdWrVqrDVVWGrOhkcBARStRzrqQgl4K1zGvqHgQ09X5YEAJjEZqFVQK8D/",
        "8VxADF/8AO4xGTIycKDi/0rW/n/+3n/r/nRIvvV71VZqr76wAJrBU4IKPNhj2tg4v+Ay/JJCFG6jcYzcDodoZ0BdDHRQHgt696U97YlhW9VemtQmevu9dwyn",
        "3jXQkUJJcP/xXEAMf/wA7jERFkJ4nTPP5yq9/+32//H+UTLrilaqfPtOefagvMZ9WoDgb6MKpBzNxuzlcB0YDT7JRwEBFf5BRKqQc55wVPUypNRZa+KElZPl",
        "AklkF09v0LJgdxQ0oVreikDJv4D/8VxAD5/8AT4xACpbOTkIoUE//8df2rjPH/x7//n+vNSrWq83rrEVIDN+n611bJRUm6pSSEmjrQk4uwbEhMFLGQ87zzzy",
        "QljIGc97yHkgz2kyVgJC2ASOG6Rx//iZZJqnJ5BBq7MKyEisbERH4YYzatVx7l8sVNWBKfiP//FcQAtf/ADsMREuMniddT84r59HAQEW/7b/8/87S7pvrJFd",
        "8Su+sB695gJevXvynbN36t/4c6HPPPOqM6p61TnsnDWpgUoNYF6gpzvg6D4D1OyxG90VyaihEugAt//xXEAMX/wA6jERMjJItVmvmsr3/+Pn/7f5XSI54q6v",
        "364r17UK+TBGjdA9Z6zfc/2qv17AN3ft7T+8SeS53d4JmKSvXrDqY5a45ppJQF+sOJh8HT050nDX5hnJB4Zsp2S4//FcQAyf/ADsMRD2UmGpJkcBATdjAP//",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////vztWf/2+f/b/aF1KkXi+9RlgWmw/CLSBh9ItxAJ4+NH3qWAF69Edca6OhdB2qMDmfMxfSD8F9qSLbbV0pGBjbSdNI2q0NbeZ5+AQVxTtNkxxjanA",
        "R0EANQcQAANT6n4AAAAB4AAAgIAFIQAfO9kAAAABCfAAAAABQZocBd/OkKUXgDPlcXA3ofs9MvbuRker6XmTL/iespVgx9VQBViz1/gt9Hnr+Ybn/c9A44/D",
        "w/R/hDUE47/xVl2M4wocH6iOmEF97fy/+WpV4t88mAz14qeNnZxOPib/YrrMfPc+jFVaPgJjLzoD9Mb7/guD6j/rhE8DDoAXC4fx/UF+ooPwY9AxzsF+wYxg",
        "BUdF8SIXgvBHAQA2PAD//////////////////////////////////////////////////////////////////////////////yJc2sBPVgnwmw8dm9/vf8PL",
        "YFEHHPXEIO+BGkL1//gpx8F0JSxWBCfD5d8IcDsgFBxB0UsGSl/FetHiTQgEq/JoPt4MNfMP4EiIDIzW3xVvj+KImbeoq9Sngl8FXVB5rwGBLzyIi+Md49YG",
        "ZgE/irynh+ocATSvCB3lgEdBADcHEAADZX5+AAAAAeAAAICABSEAH4IpAAAAAQnwAAAAAUGaKgFX4DAnST41jCXKnbfWAu+egZ1+N0c9l/+H5uBPP4Ff+DEr",
        "nOBOUyAFuD0GPwwz3/whG589/5uvmvUcZ8II2jK+OPhDj4p/XhBfztl34QQbPhV8HVoOrf9oNACpsJ1x495UBu8v4E9E+1f89j82/P89j9Dc+r/VEWoQ1GyG",
        "xn8UDhAk2AGAYt1ilgxUv4/NgawFG1WWRwEAGL/wjthTYh0iB0aNH/oGq4fAhngNcCMp88//ASOeC+lr9nBYQToY79tlfugfAKm+FpAginsJTIiBLvwQUFZ6",
        "/p6g4C3J4//ffwc4l8YgUv+8GIem3rg077rzguGvwxo/8LAx+DvTAk/QJ831938Hh4BLEu/1/wYBSeVP4OLhq+UeriCBIQQCQhMiEziBMiBM8QuPeSTryQl4",
        "PJBayJ3IEOITiE4mZEzOJJkSTPEL2e3wx983A+ResVBHQQA5BxAAA3cSfgAAAAHgAACAgAUhAB/IeQAAAAEJ8AAAAAFBmjsBR/noDH8CQZq14rz0A/8QwhCI",
        "aAxxiFrB6e+IDABJ9DDpcJ///noGOve13hBT5b+mLfz+Gy/U2zGQ2fBkg8eMXcnHw42DFxCTCu556mh8Ilc556/r8ZPVEBdQgSJ0IgngfiTp50M8Y3BrCEFN",
        "gGHCCQo/8+aEmsIbgShdtv+EeFPWS75t61AYA48DuMDcxS//A2BEM0cBABoUZ+fMKqQ97/zwY/ASMvzecGASKtQZKWOhGf/QMVY8DaCPsC0BxW/wMCtXBj8C",
        "74CA19D8B6b0hKQgEidcUGKHmrv1yqw0BhVL3rH7/h3PBPn5DvnuSvr016BQgE7zxgoQJV+mLdv2r+p4GdCRqejVflH8CUglJ2+Dypov/+8CH1aXgwrzyoQL",
        "r8WibqlDahLkvXHfngLfgwTaO/PACAEW/+lsRBLVQP2q84e4lr6n093sBWRJ4fmERwEAO7QA////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////8tfUBHQQA8BxAAA4imfgAAAAHgAACAgAUhACEOyQAAAAEJ8AAA",
        "AAFBmkkAVcttzE/k/gUfzmELQihxTO/ELACPTCDnz0AX8hM7mvPSj+Ex75aJ5N/56Cp+KXmcf/9BsE4rve+iCl7baacIINUS/xeLoQgrMd/0HizeEf6otfzp",
        "AD5BdXx9YC6qOPYQzYNwygB/Np0zxiwYZWifPA+bxRf5M7Bwc84PHv6uEIEA8iRPSpMNPfl/wJXmX6vQ+qAfv0cBAB0BXb7uDAGHcLYQWhWnJvA6Msv+DfwQ",
        "Ax/UVXiwXn/IlsDn5P9ZgQ/cBQ/Av4iCuXzgsX5F356/v+/EIGfhcb3oGSRcPAuPAReAWtpTz7/Xu4ChUYp3qVO/qAgeuU798ghA1k84NQDiBdfi0n9e7gcV",
        "EUhCNb1fqBtteDKc6B3fi35a//xCLhBCjcS4HsuJwil5DwR9h8GnboPPk+6/zoqCln+kX04C4h8BjKBjJ1rRqt63vz5A7vxVRwEAPqQA////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////fngfrxb//Z4I64Fz0CuK+T5oBHQQE4AUAAAAHA",
        "AzaAgAUhAB8R2f/xXEAMf/wA7jEEIBQ1kJppXf5xU//tfp/9/9oNbvjeTjL9cWpBUKA5cZfRbDjLvfJQfyrgAwiiiIooikxiBRRPsQ8MSQhC7qV6bN3U3GLh",
        "pAheMZszUaOlN+XCsAHZSRh13P/xXEANf/wA6jEQ9lQ4oU6r79SV7/9vt/5/87uoirnOkJKAHZ9XhhNpk8qjJSuqZkAN3ovKDe8JlpZsJpsJsJpuiPjTikcB",
        "ARkysbLNlql2WaLn1qKEwUWiUxNJgTmdb3iMz9kC5CYXFICVIxiGuP/xXEANv/wBPjEALGsqDN6kf//fHfN5X/4ft/9/9Mbtd65otWairABJ1kwG7PilaoLn",
        "ovOxf66GXzKowbIOBhyJWFIzabWzS38GSUzNe6UNiECTAfcSMxmjBarFTGESqF+iW6goDAJicEag7uD/8VxADL/8AO4xERJCkZDzn23XPP/j+v/7v9KXNc8V",
        "WuZL8cR3RwEBGsUMboFrG26JE5cl/O+Mr9EyIXXnmMYlJoOd4bU8+DGJgeT+QwNhSXAexeRYDbHhetan0OoxOrsesRUinJMtSvD/8VxADj/8AT4xACx7IS1W",
        "//+z+1TN//h3/+ftkXUXU54vFS6QAHd2fP2EZGV9vN704P/ldnnPq85ZG0+s88+yec9c6+qcHP6mPU1AguhKhuGCS5ZUyJ9YsgEKhAte7EzmU2lr2S1c0Fma",
        "WN3GTS174P/xXEALX/xHAQEbAOwxCyKVzx4zffz//b9//v/+WLl031MZ166q/n4oPHmxeeeeSlhgrvS8ljHu9nenTI8kSFyF2LJWOMJMK1Oi0TwY8MtzW12k",
        "l95TiLGYzAKaKcD/8VxAC3/8AOwxEQ5Bsm2877+f9ft/t/+lUutZ1jfDPHUv39sDWEwZAGJBin8n+G9ghT2aL+X8Gi0W3Rvt/Xk7Iywttt9I035I0tIMKHYt",
        "RcrsU94xG8VwlAtw//FcQA0f/ADuMUcBATxZAP//////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////8I9lJJtarPSnz/x+n/v/mLqLqtZUlXkzgF40xI7v2cWxEZfsfZwney4sDE5yiKKIiZF3IL9p2tm6F+ht2vNC8J",
        "p5+xaf2+j18NjhKbee9E0NA/0LR09lpodXQXwdhwR0EAPwcQAAOaOn4AAAAB4AAAgIAFIQAhVRkAAAABCfAAAAABQZpZQFXGE/l8fCPXgzyE/IXAsfxCxRPl",
        "/88NmtNDVQibni+DgogxD/wir3KAe6oY5QFZPk/9cgBonghOwEREl+LYPVMullhBcVtv8/n+Ma7x3v89O/kXwevqgMAFBXd/wY6qDP+PWxRP6joLcCkzwO+i",
        "Ez/k/WBBg/4z4MfgKP4BEZq6+fgcl9XBjr/E+IgjdH6+hb3krk9HAQAwSwD/////////////////////////////////////////////////////////////",
        "/////////////////////////////////////0Cb5l//UyECVVwa18GqxCz53zwR/4+CaaBRP450s5f8HnWnFhBRhrwP18Uvj3D6mAWSVin+eCPrrgu5WCxB",
        "4QTTIT5f/+oCCElH4xQfoN74TXq/86QCfjXcnku/9QAqrvgUr88iR5Jq/iviIEdBADEHEAADq85+AAAAAeAAAICABSEAIZtpAAAAAQnwAAAAAUGaaYBVzWs5",
        "P2X8DpPKhCY/iTD2DHwEt/mvnwrWkHNq7H9IfB0Ex0i/O0Nd/g8tovgxOuIIl+DiEZFLzfNxK/6XVgZQMHVAcAIKiLSifX/nNdigvcChhXP+CQEa94MAQr/4",
        "M+SAlOT8IYj5SfVfwJ57cQmv+AxV98GPwX838Bd53l+I9e/Ud1E+X/zuiBdfxa8GPN3+eHeoRwEAMmEA////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////Iuvr6vO3V9L4MkHu5QOgCxUM5QwGj8uo",
        "BwMc8udAB/hek/y6ucuoGHF/54dlvz/fU0FnUAu3MBxAbWzFfOGgHUSO/8urGP4IEcJwawLF/+c8N9cl8kBHQQAzBxAAA71ifgAAAAHgAACAgAUhACHhuQAA",
        "AAEJ8AAAAAFBmnnAVcy+58I1TLhCdoWb/B04eGP9CEGy4LHwSQxRRGeeHC9JvwmcsA+3/FceRD9EOL/C59oAzrS8BoV7m4zz6Av473hD869iu+qAoAUT+/Pp",
        "jXqz/Hylwl9h/B34FIEfPCnP0Jh3whiK/pB6qwTD/F1MDw8DFUB2jfyecsn/nYMcR0IeX7vpeHaDj5f/9KST1BevdaxckEcBADQ7AP//////////////////",
        "//////////////////////////////////////////////////////////8aKvz5zeP6he+Z2G6O9fUmcFBv+D3S/gw+DDH5+Byut/0IQMevk0CwRacoHgKn",
        "0QAJ1+IDog7UvnRo8/z6ffBypkJaov1KrRv8//Uudxfg66bkDujw3R/wPIDo3+cPLD7Tf8kBQqH6ICdedcq894xLcZ//lk5b6EIP9/fUR0EBPQFAAAABwAMy",
        "gIAFIQAhFxP/8VxADP/8AO4xCCAZUTzOrj9JNz/+19v/f/a6ritZdZJKqyroN004RMTs27Ou7jHtP3yf6EhLooooMFrowWaDcNfQxZxQKFrMM66DLdWaS3Jj",
        "TkRMiiFqJ8W54HhUn1hivjJ8JHV4//FcQAu//ADsMQj2UbNcz3bnj/4+3/X/rF2N9Munjyv15wLQXyJGU6mOsRfZXh4tXlAEa6tVa+er0UpV6Kq6vP1HAQEe",
        "YXfhSeebkrOsHYYZwohN8916yrs06BIiCiRJTv/xXEAMH/wA7DERFkOyb6/Lmt//2c/+f5vNTfWCJmaOeMCXDEraEidcom6ER+4IvMDxQYXSdVPpOhEnx0jq",
        "t7TRcycetodSlSO0nKQ+rsXX81IxoKnBqneNgw3rEiVvwP/xXEAMP/wA7DElhNFKrflx81/9f0//f+qJZrm93c9+mvf2Cys6ulXWrrXu1e2e3eHv+X1aMnnP",
        "PPOrYUcBAR/nhQcT4LUpo5lkdeBYNWltMETVKAujU30/bwzEjmuU3S5ypaNu//FcQA2f/ADsMRkWQmmZRuuev4znXP/9vf/6fqkcZVXUtWXzxKCHadEp3mRk",
        "ZX70ELCF7mZZqQGgp5555Olx4YsS9ikOI70yJQ4ED83drcat+Eh5SlYbsIIULzzrOIw9NKlYQRtVDMoVFRbg//FcQAz//ADsMRD2UnGhfGfo3rv/+9P/x+rJ",
        "LxL20+3xFShjf+GfRwEBEExYYGMbkY44ByfpUdAnWxAuHrPP0NT/quOjmrnowOc2xazGOsGOuOqMyhXha5Rj2pGl1lq0lH8uHWcQRiGRl4D/8VxADF/8AOwx",
        "CPZSSLTVfat3X/9n3/9f8S8uS9ok3vo50E6ft+0Sfs4naJHLzH4sJzkcLAyIrv3cSZEREnFkROqwdZbmeuqC0M7PIM04R/OEpwwoJwfnjo2lUPBnmSJ2t//x",
        "XEAOH/wBPjEAKGspKVj//vf9ZE9HAQExXQD/////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////6/p/7/6Ul1KtRM4qCg/C/PMEn+ZXbFJ2QumQculHtUryUBdNFFC+g1GFB46FjB1o3OJgkikgJtoBCaSn6u",
        "mZhmFQubrTBSm2I3eU1FsH0SxqRAVcyM2kgL4EdBADUHEAADzvZ+AAAAAeAAAICABSEAIygJAAAAAQnwAAAAAUGaiIAVcbNnv/hHufPCrYUm/ywl0GP8Zi54",
        "NyXYoZs//PiEKl+cf8tQ10Ifcn01/noufh/oyBVs1Nxtk83XBf8GPwY89YjjO/zmX8lDlr8IVt4R+UGOuBRX4Mc/nYKYj++V/oFTU/gt+DHiOb6n1u+DCplP",
        "askI1pkm5lfUPqC4DENX+oHDUGw6BitEJrNn+OEv5/iAxr6mRwEANpUA////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////+5+Sgj+ZRBkG6+JXvmUiHBPnXDqBtV8Icl4Uy//L8/AgSRHQQA3BxAAA+CKfgAAAAHgAACAgAUhACNuWQAAAAEJ8AAAAAFBmpiQFXG3Ao/q",
        "VBc7Q7/GuuCM/Bl+YTFnJ884Hngm58Q03/FfPq4HeedDIjdj4C9612g+o/wNSoDs8L1gLKcKAbsBv4XxvmhTm+I424ChUZTvUcN3rTLwd9wFDz/EcVJ9/fdw",
        "FCvG1vVMt6lVj3r+CP3nEQQ1yyn6vx8FUCRCAyM0Vb4ossOEVg5MAoLw19JNxBBKY2lKuUcBADhUAP//////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////vXvAoAIBSL71HbvUcbvXtHeB8BEpl5PPZP8/lDjX/z61J93qA6A7",
        "J9//xPUn396nTtQ3e7iKQUFV/ivLAwrR+qg1A6gVD4nX7Z9k+fgz/0f+PeuEv5/+X5eBg8If17VR4mtXR0EAOQcQAAPyHn4AAAAB4AAAgIAFIQAjtKkAAAAB",
        "CfAAAAABQZqooBVydgkyztc0RhH+qAivVAaOXBfnNRLP8Pm0wjwLcQF2vCOWQ+jsvGe54ThKaEIQ4MTuvhP41Qv+DHR/494DXAR3O7z/xPGfSwfdXPHjvgxV",
        "vgx+DHn+I4g8NxBf4OfX3wYqUXNoPFFzXL9yQFhydXyesQwa2/gl84M1HY4nwZ8+eVPCuX+s8JaUc8mf/nr68RBb8H1HAQA6pQD/////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////yD4LHDccefBJfo/WeDW3FXpf0dBADsHEAAEA7J+AAAA",
        "AeAAAICABSEAI/r5AAAAAQnwAAAAAUGauLAVcuJIrxHrRWZdXREzET+doDh/cCi1mvGnwA3vU/s/Uf6oBDqPVoT4Mfgx5viON9Yr4MdG/o3+f4j4niL8R15x",
        "QgXIVhtFr+X/jNQgT2gdQvqj74MeICOJ+sJZeDFRrL8NrEcT4MVb4MzzIMGt+rTUnnR/+pUyfp/6mRVkzwtCRRX93y399eoBK3wpqZDFSfp/58XHRwEAPK4A",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////////////////////////////////////////////////////////////////7/JnhO9B/",
        "n+BHQQEyAUAAAAHAAxuAgAUhACMcTf/xXEAMH/wA6jERNjJBuVHzkz1/f+3/v/tqkdVu9euE74k5uAdFJLjKi+TAxdTAzmGpygAwiKIiCIiR+yqO3zTvs3XF",
        "YbLgT6tmFVIZ7ydVWmCFYQ1r55eYIFZpkmXZp//xXEAMf/wA8DEQ9lIhyavX7ZvX6f6/P/v/i4mXd+NNVWRN8UMsNt1zlCEpmEZCV279oRcAPFASTfSg27XE",
        "tGfFFkLajFq220cBARO8TbiszInqKusUMRe9OFeb14am9DDZxXRj0vj/8VxADF/8APAxCPZSSLWpnzWPX/x4/+f9MiaoqVrJzwv59gQ1bsPPOKiFUgz18Gz4",
        "rFMBvYc6p1VTzzcxTzTKkXXU8Rf9u8KUUvTKMM4x+Syeakodr14ixdy4I1hSF7cO/P/xXEALv/wA8DERMjGzW+vzvde//0z/9364vfGNXVTXfr4k9dBkLq/k",
        "7t272vau9+A3fKN1r69evW+CRwEBFG1+maR6c3grZhT8OtJD8f/kpC6HA08XdK15/OgxHQJiArz/8VxADb/8AOwxCCAWPYyegjKt9qZ4//D5//X8UiVe71VV",
        "qpSoF7pFhASlZdtu9gZY0SzrEacQPb1n6p1euBp5woG9RgFNHOZyc4JRlzhUaQbzqbC03QLpJ1pj1pxa9q6cn2Gq0rQSlWZrc/t+//FcQAvf/ADsMREKQnCh",
        "xvPVb7+f/29f9//x0zjfFa3U1U+3ma+eoGhHAQEV4bA8QMDA1ur7nAGZy06dLESMIfspru8CKR4Dk9zouSlKSm8dRNm6nAzOml+WeAxEBUd5Dfz/8VxADH/8",
        "APIxERZCcaFzX6GZ/+H8f/P+lrk3pJuJ46kyUMIG0mEwZpxXaCuwNCm+QrwAhRRRR0UCg3QYNL6PmI6+gUdQC42oxOqdnWCpGMZOsZLK9NrTTnb/Q1jAiIpL",
        "wcD/8VxADH/8APAxETIyWKFG1J+a5vn/6fb/2/6wjVRTrkcBATZ0AP//////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////924qogWDpNhlll/y/mp9S+/x9LAZERRdxF",
        "iRJ4xPBH8uysylVLU6uSsqlA1Rw8vQ+XNEmJXnWIh76KuDFiNKDJdkE8R0EAPQcQAAQVRn4AAAAB4AAAgIAFIQAlQUkAAAABCfAAAAABQZrIwBVyxJ/Rs959",
        "Atfk3PtTBj/KIWIJ/E/57jCaba8/BIOX88N7/jvWB1r74SkgNFcufj5NRhD8PAxWtH+qdx6MO+A5jAPgczlx9qP4CICOF2X4NXL8X54KYpl4/S8P0CqsIOO5",
        "hEswQL4OgjPFvJ8jJA0QGj6puTXjayaucnz+Igtm9AqKn9hG0yiAfhXL4MVLonzoGCxHAQA+VwD/////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////wEAE0hp28mn98mvAXlA4BFb8mo43JqMFOTUqegVnh2kIJLTFV+b",
        "OwEXgFraU84ejk+av9SjDwIC2OoGZbutKv4iTU6cmp018Svsv+BS57n8Bu/n7rz8T2f/J6v/qnal8EdBAD8HEAAEJtp+AAAAAeAAAICABSEAJYeZAAAAAQnw",
        "AAAAAUGa2NAVcZ2tAJycQIWI88olHAj9Z78N2/B9vK8HqsI/pVvxeNWEf+edAE/5F6sv+uQk9/PQA+AplbPqK4QP3FcbwYrXwY9QOKyVR7NAkFgrDJEJniBM",
        "9kwP3GfJwYr3wY/Bjz/Ec02eAiUc2E38+sv4hG+vfBjk/P/8v/BVBhhImBmYgLpq23ttyezNQKX60YIeCRb18T6/RwEAMKMA////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////y/8CfHrn8BRVyJEuBxBApzfGc/VHQQAxBxAABDhufgAAAAHg",
        "AACAgAUhACXN6QAAAAEJ8AAAAAFBmujgFXGBCYyABEDmfC25rsdC0F/wpV/C3+UQsQT+M/1zeSrj57j8CF+meO49Zfrzj+EDw/KPjoBwD8G3L4NnLj/3K3L8",
        "rOXjLgKHn+fxbMXuxrtzIqgpq9Rpu9GHMb+DNW/P+cBb9s/tPgKHjfP8R8TydqVFWezmFzxhwyq/1AxK+EOGM9GJf/zfdfqRHH4Z7vbwm/P/rEcBADIhAP//",
        "////////////////////////////////////////ATOBMCR+QHEJ358S7+b4HEEKlTHv9xngkfptj3K+j1DuWCSTAz3S1gFwyWH5P2/9R3/Bsf+YyXP+BkDh",
        "4JwptfwYP3zxGYQsRP4Fps0r3/PUut/688EMr96L/+o0BTJ9vwMMCPnDw43+HnafHOj1GmoUO4D0H5o9iIIL7GZ6wmr9dYQUb8EgqQiB4zIOL3tecDr5whuA",
        "R0EAMwcQAARKAn4AAAAB4AAAgIAFIQAnFDkAAAABCfAAAAABQZr48BVxl6sfAo9f/8ZVKgO2v956BnX8UXn47hM8AJGCqqXwa3esfN4QkgPbililgVTRtHmz",
        "3HmI1HYQOg/KLh6EWaCJmUZwEQmWMieP88S04tk3/BiteD4PrsZPKb/ztEFL8UsDyLo94DbhENz/O9iId4rsJQ9DSGg028HFaJCZxVHNS/8GECd2BkA+HoWS",
        "8ISrw/vUdvhHAQA0WQD/////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////NvhP1UjOvKeciAov4QgjQHTLpPugf+E9W+DHRvq3wZ7MuBB0fwNx5hKOHNLwifD8GHEAIABEqQTpeoARoon1HA/yk9Kv9R3dQfHhdsNU",
        "cFR6REFvTuC2pELrDihmWEdBATcBQAAAAcADNoCABSEAJSGH//FcQAw//ADsMQj0Rwkg3I1+0qs//b9P+v/upXC+b1uJzqN6oLTR9DUfQoyqkTvgfSAu8kh3",
        "a6KAs1AdY27TzxsjS1drsS6RWC0t+PRbnY4RGMqZKNrmqnfa3GpIm2yZwP/xXEANX/wA7DEQ9lJ6nax71k5//b9v/z/e5S7xJWqrLq6AGkDBKwkDIWJhjoOZ",
        "rbN8zOlgYQz8eM0yiinU/OBkVsGB0P1dRwEBGCj3OZWIC0YgdVlpq6UolgRVrAjFXSo86NRRurItdhKLRhTg//FcQA3//AE+MQAmWzElWv//Ov2azx/8e//4",
        "/el1rHHeskVIIGD/JnqolFSbqlJIT6O0CTipAsQpkIeeeSnzeex3Ex0GcoJIRECiQkm2yaLmdhPTFYpCQummbBJG6xKyDP34VayAZhmtxaF1MIzw//FcQAyf",
        "/ADsMQj2UnGhbPfOdd//26/+f8F78r8XrfW678pzYfpHAQEZ6qvU887N6Z4wG5z6zio4AJ55555znB/Ux9HWGhOqw61mrEB2ltYSTkKIR1mltKMcI8DW1k/A",
        "INqiCCK9L8D/8VxADF/8AOwxEVYiMMGqv85znj/+3f/4/4Kk1u0prPf2ufPxgjrnfoYGLFi9Z9/pIzlI4AG0972nSkg9y5M1VZdVZ8ccJSqrjzaJ5yIvDDxP",
        "B4L3ln1S+28M5BCSNgpCnP/xXEAMP/wA7jERLjGzjfH8Xz34/7fp/0cBARqv/XikmnK643ffGa+frAOJT/PMAxIkSPxPkvYyQbP66NttmSOyMbdu7EuipyRv",
        "Wxkuw/tGJC3F+Fhd+toL8BtPZf8MFfnRQXvw//FcQA2f/AE+MQAseyE0yqR//9r893K/+n8f/P66pcmcYXuZqFAAasVyBBRaNPrfkhr6DHLQBLWK8FgZEUUU",
        "QiuciAixLuyoLvTMlCVsx7FxfMHlOCtbOddSbVCqnUkqg9EtswUC1C06AmeA//FcRwEBO1kA////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////0AMP/wA8jERMjOzSeO9uf+39P/t/pqpK1Vav153PXwmAxK2JcJp",
        "tM6Zj++/CPzDaQW2tqO1tRjay0Ytyx03Fo2KVtRZNKYraMY11mjgtjx46te3BbzERw7SKMy0JcBHQQA1BxAABFuWfgAAAAHgAACAgAUhACdaiQAAAAEJ8AAA",
        "AAFBmwAKuWZZ8J0ZnrH3/neXCJba/XnpR/BNu+MbJ+OOdREz/QRoHzXzxXC3eITQPM0Jdd11havrhg7BbXnBcIBKjLEd/H86Tan/4MVzHUDDz/wNM3ngIvAk",
        "FqnnGf+jwkob8ZN/XwJSlJVwkC5ToEeoF48PqCx5NHHl+ta61In6xVqrq4Md/B/l/4+OPXLQden+DBSp8GCvl0cBADZuAP//////////////////////////",
        "///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////g",
        "0AifUAhCETpL/wXQaKdFSCRMQMQiNf2ifxftf/UJSYSif1CzwpG/n5uCF648B/O1cv/gIFnzeCynEO/28DDqG/UT5iG/+bmgR0EANwcQAARtKn4AAAAB4AAA",
        "gIAFIQAnoNkAAAABCfAAAAABQZsQCjlJ/XnjfXHiFm9eB2Tj4CQxMPx/HnD1Fj81wCHpFa12Pp0q8HQTHjvPX4InvPL/+uRFiaO8/HyfJxHBxr4g8AmMT3/c",
        "BOKPu9R9yQGjx/KeC3P80InBqEpMLuzUBCigzLCLmwoPSl/4OIEjsMAJwM3fA2EGAZ5tFL/yAKIDMtHT9RoyLxqkR0q+TUc94eBj8Ha5fBpHAQA4TAD/////",
        "///////////////////////////////////////////////////////////////////////////////////////////////8Jnrwis2++CIBgVC7TWBvBBqI",
        "Il9B4DAvdavk9Ufg59X+HliIjWOzwHUJx+f/FwIauCSdk/jf4Aw0Nd3AyM1irm34RlGdAmhBrCQovwKqsOJ7wGFOgeEgYTP4Kf3wOIIFIngbwQcviECmeEdB",
        "ADkHEAAEfr5+AAAAAeAAAICABSEAJ+cpAAAAAQnwAAAAAUGbIAo5Sf198/mS1iI/mH9f43xRMEcWPgmr9b3fnyNkpkuqXZTIgdCPJkohWjxJ1kw/PRNoQcUf",
        "18HQmPHl//P534jP+e6/x/f492o7CA/iWnE9Fv8XypIPWFbgptc+8+5uboOdVA+bwdFv8BMJX+DD4MFOn61UVzD+vBN/z/Bh6Bh8Fy/1hwGlnnQkl+LYt+LU",
        "fBnfET8ARwEAOlMA////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////6K+KLJqQ988aoC1+SN+/DlYOgQr3wY5POb/ztfwJfciyt/HtOZOEj8bv6+DD4MJYyDNc5vw/+DOSWA4VIlhDD4yBgByQNIuEe4KhknFuX/AQMBgzwGg",
        "qZx3iO/gjveVKn+fiIBHQQE8AUAAAAHAAyeAgAUhACcmv//xXEAMP/wA8DEJMjJ4nS3y536/1/r/+P+dPPiM87Lle/Wp61YYf8Tz1Zfl8p/xXxe/q8DY4/KL",
        "YjLVEEEHxxkIlvzKnSfYKtktKA/AQ1Ia7PBiRk0Vn94ipBEhd1o5Ry//8VxADF/8AO4xERJBmY1r/Sqr1/+3j/8f9FResXlXk59sm5BdvQcRu3RP0nLkvC/p",
        "FfomRg+HwlrlKTW19OCcO0+mtGXpG0cBAR0RWnNKgw8NG5q1teSVJW7zWnPzKsDATo41o07/8VxADT/8AOwxECAZUTTSq/fdV6/+nP/6/FSU4VVXrHfFzKsF",
        "Ji8FKut+6+c+Q/k9//f5O62HnnnaP1HUo6p1xq9VKnOdQQ+vqVVJWWWQxuw07O2kglfeJcOXosf9NwSxsJQ7CM44d3z/8VxADF/8AO4xCPZRskzvvK3/8e//",
        "6fcjTbrLrNeOk9eQveY8888YjQN8Of/GmVFASDheRwEBHl+WvXrlrlLOmmZ8csuaby63pzUVtMl8BqdekPy+V+GPXXi7oDKcn46UHgoUrfj/8VxADH/8AOwx",
        "EPZSYamnPuqd//Hz/8/rBpnnxaMS3OsBRIZDMBgYnYE8AK/UYCBHKpVcQCw9Z5zYRzx10R+s5/XeGhurRQpEpJJWSkil8YRyWWlDEW1Gv12WTwk9pgIgL8D/",
        "8VxADX/8APAxBCAULZUSrXV/smb/+nr/2/0VqrrWJvVTK4FC2w9HAQEfQ5ZfkZxbWHeX2HUx0FDCXFg3LLLLKoyZjAzJmUmqUABBsbsJXDMipFikbBzEpBVJ",
        "JlpC0LQVLI91rwoTRc3VTE2CJL7/8VxADD/8AO4xERJCaaV1x+mbuv/2/j/3/3sTjLq8up44jLCmaDvuy5pv83N4MfOfUH0khCg1AWtZjChd9a9amljBZ42L",
        "rNGytd5thCOssrZUEpaurLvUcKOkxxTlNGvA//FcQAxf/ADuMRD0Rwi9TpNfnEcBATBoAP//////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////+V6/9P0/9v99Rcy8iZbNRl7GaKvpZSLSxK",
        "olkf1ro6P4cEVdWr3K3hivB6FalUK9mqqsE71IAjuMIilmFLVqy5pEVTCix5WROyQssSBYvgR0EAOwcQAASQUn4AAAAB4AAAgIAFIQApLXkAAAABCfAAAAAB",
        "QZswCjhqvvhLlPiae9+Ai9VXP4k4qmH49Kgvzt2GV4RjuEbl4wawZv2PgygfMD545woinfAxFJI94gBOgijPLL4bi034Exa+BMWpI3xEEMnnDy8BI/Tb+CAG",
        "HweLF5p/EkjGSb/875V4e7Vu/+p1T+c4DoDol3g1cv/g6XugLQFBKu4CgXuwYDT+hvu//yf1/BgsBv9Qx+JHAQA8LwD/////////////////////////////",
        "////////////////////////////////Ql3PGihARV8Vn1+5YEc9v8dzRfqLy7uAoVrHs2gI8E39nARXq7yz+DA8JaQRj8sXzwv4PlOL9YOi1GUfrUiafAr1",
        "Om2vXuLBzyeUvB3+pF8YMASX0uTIl62wjpgkAMQEdeEe5+Ca/ZHqWQaKMNhGzQNDJJq5YKrQsq8BLVIo8w9f84FfzcmfNEdBATEBQAAAAcABNYCABSEAKSv5",
        "//FcQAwf/ADsMRESQnCha/znO6/9P4//P/MM4EZpvx8W+fNANO0tEiRIkJy5L9l+iV++ZELzOdvXetI+l/ODLNnWs3SL3ReJTNMtiWlQXdXBxjDMzYcioUP1",
        "XwoFBC3A//FcQA0f/ADuMRD2UXqdes+dzOf/25/+f1lRdcMvdytuFQMbdy5NZe4szUkMKDWVphe9voTAnv92/fSl11Lsnn05Lrb7oK25RwEBMjIA////////",
        "/////////////////////////////////////////////////////////+etZ6rHKAcoISCFLa2FLmKucqKhX34RMUZLIgtNKAXw//FcQAy//ADsMSWE40Gp",
        "+d98d//2t//p+qruFXOdVPn2tkoWY4bNblrq6vdy93nXb/1W78u1LKSl5LHnGXJ7+9zSwOMWnSy5DGMgESEMaCYo1FE6IsCkLT3fE/EGiwbLBMgvSnA=",
    ]

    static let seg1: [String] = [
        "R0AREQBC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////9HQAATAACwDQABwQAAAAHwACqxBLL/////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////0dQABMAArAXAAHBAADhAPAAG+EA8AAP4QHwAC9EuZv/////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////R0EAPQdQAASh5n4AAAAB4AAAgIAFIQApc8kAAAABCfAAAAABZ0LADKYRBATsBEAAAAMAQAAABQPFCoRgAAAAAWjI",
        "QjLIAAAAAWWIgQCL/EcGBTQm4o0kw3wzHwgC++/hSU9hXJqW6C7JDpDTXwp6DwNAgAApPKo5XREVkAR1pIElUsilcesGEUBZF+xSTTi/n3HppwJv77iitMif",
        "RO8dlllykH1RSa7yrpFVucQm/tG+7u6ccoppEXcRigpHAQAeKaNUZvKLJnqqHEOkY2qpA3d4tM8CSctbCIythMAlOti7VJ+xEcR3VEM2ZD35shLRqyLVKb4Y",
        "tgkI7T+uYUAmGLbog6zfOL4iYguiGQf+y1o769j1I01U4ZfWRHEc9eaCCX7L0Q7ApCtqATMWCHy5ipdVg2TfiMxw8qfhsTDPsEVbpQYI/gJrfD4Mj1z7mJ49",
        "fE+KAAII8cAAQTo4ABG42MjAHASFImCXEABExeLweBsQeBsHkAcLu0cBAB9wQAIjGhAJCHGQsKxAACIyEAEywSN+fjMHS4lxAACgB61geMlzDxkubhMVvwAP",
        "hD8FQoaBjHe8pVzKVczoP9tFocHaYiE/8SWIksHQ9Rx9rDCDwTsc/69cEDDWF5mN4VbkGZiM9PT10xP+n+kOHb9cClAU0AkrsViMf6wvyGQskswszBimL/6+",
        "FngQLXby73pJ5uuewmU24/D/9grFzfVlZfrrwhwD/hvzYviTQGAeELzbwkyaEzOWRwEAEB7WLQQDtMLCUEXrAIu9F2paBMHVrrX746W+Ct3aaCUmDAMQ1LJc",
        "ucx65Wdzwt//BUtRD6p//T0804e8AKEtJMsL/7/+aDNwlaz34TMbcZGIgNJgcLFiWfubj2hd0W1LsY5LgRmpiFYcaXCETxO3AKs0ueFwzLVm1zwtCMipRvkQ",
        "mvAgTMu1fHSIu1euIh3JLR5mZepnrmYeNz1oP1zPe1me83SsXD00GBbHu4St823f2re0e2t82FZHAQARmCRhKYNm1eM3IkD7/XsQdH4zlTzb/FcqdP6h+unp",
        "66euunrinrY7H4WgkDuW/9tvwkKFA5jwPMUsdBGcGKlnhMi8e8EhY4SBILASP02AQsihwdsfpsBDSrgYzgXMNzKYHWBT9987nMhUe/jOGP0+xxtRfjHmT1/U",
        "EtdPT1080L7QtBqAket+f/6aYBwD8G3L4NuWKmBIOqAPAIQDC1gQvwUL/RkeRQuzSMM+pxpwzQTsZ+3/wmCHG0cBABKAitpd4VvYWLgPwkfhMs/8d/4eGin2",
        "qxfDAEYfAjgV13VECztxqqVR/v3jXCtqBgGkAFDiRMhUGXxFodicG0TQoPjBgAEeE+Cb/gTdnjv8BHr2wTdvHBjHNwOMAICwoRI7aCCn2Gb4Y6T0dV5hnSKL",
        "zxqhZC76hmumMDtMFQxCsyCsbRvvG+4qy4FbQV6Xd4QQ77V3eCSHRngL0Jy/p/4UakAwNMoEZnzwTjvnng27ho/Gtbb7z+8/RwEAE/6DS7y4+GhRALbQ29H9",
        "UiODPP8tQorDESAj3jfn/+22HEzAxJfBipfgxUv/4Bfh3vS4UB8YJFj/4E2sOl/ox7Z4u8T4UnkirYF5i06en/wJARAUIBGU+eFFSDpcB+Ee4K6T8LkhEDa1",
        "Txjvtt7fA4ABDiDAWDB7/M/Bnf/jv7gMtwZeIBYSFZqwvSF0DgP379PrhdoPJ2WVXLGbQe4GAOvyaTfkekepmhRe2KeG1CWRLXL7GOE7TpdHAQAUp64rgHCS",
        "R8Q7gBH1f0AYt+YU7wVwofIEIkfCEHsDd+Yl5BSwIDKngvGfAwIgNSBNT7gy76Dnv/4CHtQ6C5CP0oD8L9NP//CiogeCRCY5ZL72Vy/jHLYSISAkRKv7wqil",
        "gThbX8SdBPClkF8CJeIN/b/whBIOKfgIr0u8CBUkHA/CPcAZLSSy4Pv//Qa9ZsXCjzgZsxA8qL/TfhWJ5/l0KV4//8EQbFAA+EAlcoQLu4pjxQAGIEkQAEcB",
        "ABVWWqBaoA6oDqgfnsXFbWNgqDNQaoKe/Po8s959NUeQzDajTHFFQwkC2Bkzz6fXQ1MQanLKrlimm3/5zT1xWIDwKAmCmAAx+J6H4AI2/6vAZXvog7grJwkW",
        "cIjU3hMGsDDc/E7YfsCcd88G4Ez9GDQjgkmAh7UOGJ7wpPP5Amp9yNZo/Sjy0CYC9q23//gcAEgOGCQeRIUv7FS/iEGRQ/nw//YK8GMg5I6vWIix2YmYn9XC",
        "NPXOwVB2RwEANq8A////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////mGkp7Wnp68BHQQA3BxAABLN6fgAAAAHgAACAgAUhACm6GQAAAAEJ8AAAAAFBmhwFXZf+3XoyFP4g/xGY5A/En+I53lfywtvC00k4JpAm/iStx/DM",
        "4GANP0wcGQ8ILKnJv/U9Enf54CLwFFq2fwYeDBX8GCv88D8gFiGBf/wbYv1NxIbn8/n9vgw0X+DBX+h36CUUoOCSGTeDZy/EOk07q55EJX24jvC2Qe8A7y79",
        "wXagKQFMJLCm4Kfd2m78GEqgEHJUykcBADh1AP//////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////rBfj3mQSyL8P+3gwVvBwuRlIv8P9L2P2gwoWByQOJ7xPdYGT",
        "EdCIJawLn0CZwRYDWn0Df/Eu5d//UiOlASmJELJAR0EAOQcQAATFDn4AAAAB4AAAgIAFIQArAGkAAAABCfAAAAABQZoqAVdk8/+Jwj/PrhL45/8cAiuASX+V",
        "fDdn/EZeB5izvJ56JY/hJkilp/gjx81EC68Im5kZi654uMs8BH8AtbSnnCM3I8gxRgAEAICueW9dll4/hkSwNqbRfA8xXOfgRFr9aiL8CoCBdsv/BxAneFgY",
        "K/iND+FoEEiZZd8DzFc1wJUg/hW0FbLhdl8Grlx6wERaeIN+CQBHAQAa2+eDrwKAIFMngxCFLh3y+KjeCGr8BeAmHvCcfnz1jE130DULBQEp8qtVVVVVVJK+",
        "PYeh9wqN/y+SzmAw5AcMfBtyzgTOB5ilngTPg8XsI6hkEVAAEQmfECZ+EN8AIxJM88me/11WD8IfBpiEDPwQg9QMv9Spx4IQYrUnBwtfn158HZOOSlUiH8Dp",
        "sNfDWT0xbzbCHAoLgeJ4mZCuXxJMgxUv+evgg01n0fn+nxOvH9AJz3dziFr6gEdBADsHEAAE1qJ+AAAAAeAAAICABSEAK0a5AAAAAQnwAAAAAUGaOwFXZf/4",
        "RzdeHwjZ/xGPP53k85iiUfxF4/d+qUivPAMvEMPj3oDfLsPe4yDHf4MPgw3+cFwqQTv8Nkxf18nv/50FbBiPCmW3S3/4KFImeWSjZODCngiG9+cyFdxb4k1/",
        "qcfw1lHrDTKBkZLY33FX+CxQDipeC49Q9plU54e03/UlwGPp+AmMaw26JeLeHjh1uLf2eL+DRwEAPCwA////////////////////////////////////////",
        "/////////////////wx8EkMFTQ5B4NuX4MSl+Pz8JChAk3lgs5rLL8IK4lDzjpDWn4Q4COIkmeJJnhBQEX2n4GghQrp/rCIQQL+8IcRyE/f/o7/oFzZf/1io",
        "fqDLYGXCZniSZ/zzMBuFmX4NuX/OUAIARb4HXJP54Jc/EHfqAT3rrzgoAWEp0TM8STPCHQHT5nnkzxZ2CXBHQQA9BxAABOg2fgAAAAHgAACAgAUhACuNCQAA",
        "AAEJ8AAAAAFBmkkAWcMH/EY8/neT1A+wfrwqv+4MVEmn67RFYc4rFYQXdnigC/3nrwCb/Xt/DwMO4CgVKt63wjwoNIBgcKeBICjbXg91hJGgOQgYnuG2XjhN",
        "+AJKbVbw8L3qG7uTkH8ogH4WZfBty4/pVkzL8rcv3AUHQIAMHYEABJXer/A28kBXn5AP/B5w8BLHC5kA3+0NdjJ5x1jwTUcBAD4xAP//////////////////",
        "/////////////////////////////////////////////37OEZuagaMbMGXgh1BJot5+g4r/H//eo7uva4PQgp0rBqDzkgEN+DWqgbbuAoFt0CQStYSwnagC",
        "oGRJi3/93fhBadQPlF8A/labwjjPwnDwDiWsVcThX0eDGf6r6/gyOC4iA7v2wcTpvzoD9MW/3JzfX4iHaHw9KgEenybH+Lp8myfIIWvqR0EBMwFAAAABwAMv",
        "gIAFIQApje//8VxADX/8AT4xAC5bMSTa///cf3qtd//T1/+vEUteu5dXW5qssC9nj+Ja6HEY3IxxwHaGVQKePaExpB7j9XV1TmUpRuig7/VHwNaUdKKFYtrH",
        "QlIPLSrE7K6Era1pb6tEPNw18KptAyQ2+P/xXEAMX/wA8DERLjJYracfs553/+3z/8/86ITOJze754k9/IYygP4MWjAwPWb4/71fhQGR3/vl+5NJEgpHAQEU",
        "L9uYoeQCku7tyb0pqpzpOBqdE5482Os80NUNQbSC2iqUJRTvXv/xXEAMH/wA7jERMjJZrSX675vn/6fx/9v86ZbW+JVXV/b2t3qDLBoMwmm/OfLI+OeVffZC",
        "NRRRRQOmigXhYoowWh03NZa1lbQtvJICiEDa03SJZL3djEevDUIFSnEM3P/xXEANX/wA8DEQ9lJ5ncXnfiZP/7Xz/7/vxLmab1XPVXzwnjihjU+d+dFL0I6r",
        "OGLF6EcBARVuoxe91xYGEUUUUWXuCEbCFiDkIiIkADi+YIVZdJzD0bWQtrNXY2cFI6+dc9Y1qbdL9vJIy4K8//FcQAxf/ADuMRE2MZGRc1+mbr3/t/b/9P34",
        "JEvLzVPXV1vVBq3HXISEhOmdclfbZgM5wPFBBw+Fsvj4MMSXK2y2y3CLUbu0kkk8WWg1JxmrFfstVK99R9mhr4lCBxJo7zj/8VxADT/8AOwxEPZTs1zr5qsz",
        "/+33/+P7q1V5wveXRwEBFhvipzxQy7s3xYGHa2QqSjHQSNxmz7POjBGVZayunmk7KTCvnvLRrWW8Ec2nmvWUkyXotLhZtbVrbb1ldjXsvJ9hNCltNLJjFo04",
        "//FcQAzf/ADuMQggGVEg3OH5znj1/9PH/6+xKu8vLSVlpl4G7jdrrq6vdz93evgf5Dd/5HK30HnnnnnkpY88ljqW7pMdihCc4UT0Z5kyfo3a4KCGBO517Nxw",
        "/KwYNmkd0ocaaFuA//FcQAv//ABHAQE3YAD/////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////AxHYTxOVfrOe/n/j5/9f/Ol5xu+eNVe3jzV+/xsIVa6VdXV0p3Hpb4Iu9eqdR/XD1PXWc9ZwdQWfon",
        "eU0jUiX1AVOfqENn70xXupalqXyXwDKQmEoih0dBAD8HEAAE+cp+AAAAAeAAAICABSEAK9NZAAAAAQnwAAAAAUGaWUBZwwf8Rv1AXH6gO8Wfzvn+SAnPgw/O",
        "bw/FZt+eItBP4t8KnP/1Dd6I47Hv0A/LvLvgwr10ENDeEAXRAgAuVfAjHgd2E7wSH7F8E1bFkbfn/UPKlF8Is0ETMtQNC98EXwRfngahAdzD70x/JLAWOMnD",
        "HgHQhMzIPmgHA+fEO8GImceTCh+AcM2CryL/ZGlWGXuAmFRtRwEAMEAA////////////////////////////////////////////////////////////////",
        "////////////////////eDtZn54tQCP8T368AVcChywF3dcuC4ECvWD4F/wme5B6NcHo14/ipgyiITPECZ4QUMZY6A5yt7il8fj9BAuqsU/zsEud8/1zcDhW",
        "C+cNEQT78VYOnT+dABCqQmZ4kmfr/BFd+v1ACzw7nfPz/iOjvnez+d5BHJBHQQAxBxAABQtefgAAAAHgAACAgAUhAC0ZqQAAAAEJ8AAAAAFBmmmAWcMH/EZf",
        "UqfqJafrpog/zQExhv//8VYCLwCI5sl2v8GHoGClIIcIkNDABZYUDzwesb4OVnCOkIhoIRlXt8FxpPnmQpX5A/fGemBQ+DDRlwYdEBzk9JL91/WHJ/DYz+D0",
        "+sf1oPvgIY9CU18gxWx4Q9AcfjqIu1f8g94B3iHfr4MDwDvFFcVWgbVOVtKHyzw0lAheFkcBADIyAP//////////////////////////////////////////",
        "///////////////////////j/Wp0sfykK2pIcDyK5/nqO4+CqRHm+Tg0XN4FYJLRx1w8BXngq3hGbD/n+OXf5P6/gMvVc/NAk4hAz8dvgxzvJw9hFAygZmEi",
        "7Ra3FFcJahoNUFBR/mqD1ReP6C1iEzxAmfCCwCQunEJniBM/hpS2dglz97BnN9VyHfP0IWf6Fv7r64yAR0EAMwcQAAUc8n4AAAAB4AAAgIAFIQAtX/kAAAAB",
        "CfAAAAABQZp5wFnDB/xGrgJuh8iiKEISFxRx3jjormqDxb4ED9RfvwRb3tEH/DwMN+BQBB5gbK+Xw8DCDr1KmEiYa6EQM43boznQdH+P4Lyr8O/GQDLCP4yh",
        "LTfxMM6efm5LHfzwDgH4E1PucAn8jxd4NtcG0cpU8EGiyf//XqmPFVfwjDV30IRK3kX7XKoG2H/PQqS+H0K1/2P4GBpHAQAUwHDHwbcs4EzgxKWeEz4PFheC",
        "MHx2AZBYfFH+gEgKUFhjFazxgYWb/Fvwfw4fFGKMIJypeDwMz9tQMAPwIHw9iECfo/CKBhEWhAEqV8SFgQCx2lBECvJhgGSs/P5lxPU+Id+zxagG/tiQsV+o",
        "M8O/c+AmagOgO5jAS+8NRWK8IFnZg6CM/8P87BLIdvk0CYiJ5NYY894/bB1QlE7fByVPwd07/PBLR3xHIX/+/ov/hncnE/X0Le/J8kcBADW0AP//////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////cV9QR0EBOAFA",
        "AAABwAMfgIAFIQArkyn/8VxADH/8AO4xES4yaKWnH7Zzzv/6fn/5/8rb1L31s4x9vqV7+wLA4f+GBxgYHrN8P31d9AZP7/b37uRyuei7yiTyYSUJRt5LicYW",
        "c+E8VYCa9SUIaIXnM1ihydcFYwXSTnz/8VxADH/8AOoxERZCSbUyfamP/j9v+f9uIuo1TJpzqnv9YIC6RIuBJpxbdhVmA9pHq0sAILoo6KOk3SZpozTS+vaV",
        "jF1HAQEZs0rJrOZPilsYzy21F10NRW+oOdiiJnGibG24i8Jc//FcQAx//ADuMRESQnGhdX8750//s/p/7/96NCXtqZ46zjcgLqIo1Sy/5eZ10/S/SvpYDRRF",
        "ERFlQQcK5EULHiiASyIZBo7zra3CGy4YBCCta3vn1tZ3qZ9R2Eb1rC8M8NK///FcQA0f/AE+MQAoayk1Uv//Gv4xdf/T7f+X+aTWQ1l1nHdpV4HAP1nDAJTL",
        "Lqp0q7QWIZF2wkcBARryghoooNRrNG3QygzFrWsZlpX2mUgPQCCG1wA7kIWQWCJBJFJkBXrtV3ZZYNkBa4HA//FcQAuf/ADsMRkuQkixw1/Wt7z/9v0/+//W",
        "6liuN1Z46t79QELIM+GIMDEzs+t/N9/fs4JD/MR5+Ytnyqyw1cwfy3noxYkHuVvS6m6Q0X4hHVhaAoKEEiBIar//8VxADD/8AO4xERZBs1M9+b53//e6/+/4",
        "Drc1iLrx1V+PNDFo6E3bvPeIRwEBG6KEgo2gF68UTChglr165zTS6YZZdfDGeN1tHyV4J+u0NFrTsNVGGqZgVzu1/WM4QMMkZSzN3P/xXEAMP/wA7jEQ8FGy",
        "1/Pe77//i9f/r+C14uTnjHr4X79ULwwO4pevXoYId53U9Vf9U1Onv379+/8KXpffvoototGEb5DtsjG1DbSgneML3k43aNjBe42mi2+6dI0Kxtz/8VxADR/8",
        "AOoxEPZSMbVG3q/0kzf/09//0+9Sl1XTcW1HAQE8cAD/////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////////////////////////TUoMrVfk7oH9DQMbBR5f0eVgKFZMcA4Waf3p0ocLuCNOBdCeC",
        "5NDNe6mzS989NjZHx1CFwoWOHk3hUH0Te7zAEkoFIXUyX0dBADYHEAAFLoZ+AAAAAeAAAICABSEALaZJAAAAAQnwAAAAAUGaiIAWcZhH/Xr3wIEQf8RQKXzr",
        "8FnhAGW/AmTgqEvYpfBwJfwjwODFCFmYMqX8AERldoij//XLL//EcF3wYfJW6wKMek4DkDDgJLh7Vli7ye3/54ClEjvCVD0/0fk88DOQU8uKL4ovwYfBovfS",
        "9JP6vA3T0Jv8TgEM7UX7L/+evibfff/IP4GAaQDgBguKLEu4oFiDvgwXRwEAN1gA////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////N6BkvH/S4AT7XidJz/1A0X56AT8GJXPCHGogUJPys7ny/RPziP37gMPJ7sv/",
        "zsHeqBgBP5LgaZvoW+3wOh9IxAmeDxmfCHEFRBFir4gTPFvJJF/frEWmbjPuf5oajIBHQQA4BxAABUAafgAAAAHgAACAgAUhAC3smQAAAAEJ8AAAAAFBmpiQ",
        "FnG+cWB8YSSPi3wdC3wbf/odaIP/nrwCb/Xt/BEDDuAoFSrQcAyKBXeKnoDfb5dQv1Ovg01fAUClTuAnlKvJ+oJgYfPVuqdbU9CYafB1+nng5PNBf+DYei7s",
        "sFp7H+INcXAWWx/y8CPPnnCPc8GmErUMFRIYAuEwee8Hnv4OF6sPCd31UR9Z0gI/wPZXONA4nt/JxUcBADk3AP//////////////////////////////////",
        "/////////////////////////////////////3XAg4/r4OhMdD+BwHgwUCgBRDooviTooX/n3I735qER/LRL4cOPbFVwcbdT/cDJngjo/yZwZBWmETI/lh+T",
        "PwA75VO58vqkXzzoiDPFXwn9i/4n5zALvEIP/nDwXMnij/gwA054JaP1wZy/R32YnoOQhoWBnlPDs/ycDdKfn+EIR0EAOgcQAAVRrn4AAAAB4AAAgIAFIQAv",
        "MukAAAABCfAAAAABQZqooBZydBxT+24/gdVfEROeFngC4nvE9JWvgQvgs/WuwJwUVpi/4d9D615d5d5gYfBhrgwB7WggZU8F+rpV8GWv1jZfhODD1IwAvuh/",
        "GyECyLDv1m1gyUuPeIOAjEQ8+vftCBD317+fgtzsEtD4egZ0B6fA2fJhDvoURTuPIZwMDeIRLLXy7+DJW/XQXkiviuifUv4C85NHAQA7RQD/////////////",
        "/////////////////////////////////////////////////////////////////////////////9Kv9WK89KfgLfmBNvzwjQ/geBCAZADC+JO/uIHSRL8T",
        "54I5JcKgii8XF4vEE0dCmKP/FQFjLP8T0JYfzz9ZwTBR1nii/nYJZDvOfoew9AOFbXECxxAsR80S0ITWL8SWPzwOHoxS/1fGcDBnQI7O3CPxEEdBADwHEAAF",
        "Y0J+AAAAAeAAAICABSEAL3k5AAAAAQnwAAAAAUGauLAXcq9goVpMR/DheJ4Ai8BEWyXefxIMNrBhAorwIvgTAgfwlovxfCKNBJgiyb4ENFXP+uH5l6/BdrPB",
        "91wYa3PF1/fFKHfK9QI1cFqm0i+DBXMJcbQYPE/b8gBp6gdhf6/1wUyex98KnoqzenEOwVip4/iwCEyICHn17+YIF+m9oScYeIAkQgE6xVCl4g2KL0BYAlK/",
        "RwEAPXsA////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////q1erAZWqdKK+KNjfkP99Hgj674VQaQDl+61yZyeKTX/k8V/9KAFrR4bzt1wYoNRTfdaRE",
        "B+pPX/4z4QhHQQE9AUAAAAHAAyuAgAUhAC2YYf/xXEANH/wA9DEZNjKZjddb+1brP/T3/8/8RV6yZatZffC+YAIBW7YlJYWFjPL5FesWaJHLID5QEP1+uiMy",
        "6z4G/QNgadd7UYFoO0yuMHYfpDRguJU5lA7GXK6p1KRBaTzEVKzsIhWn//FcQAz//ADwMRD2UnKhxWvnlT/+L7f+/+LRDrxqTNfn4IDJEh0njLxk4rth1l7D",
        "6iE72XFgZERRFyiBRCJBIkcBAR4ogEYpRJMnSxmKEEqmABSW4ggogsCAppeMXKPCbJoCWFyXcyspWuD/8VxADN/8AOoxGTIyeJ0vPW3iv/T8/+X/MjOIqceP",
        "NPn2X7+aBxBpmkiOjpIkk2Efwv75l6hIS6KKKKKFihetdDVCTXjwdwWAypv+HfNnZ2vC94QjOy2jZXrs81lixC+00SSMs3D/8VxADP/8AOoxECASLZSeZyfm",
        "Zrn/0/P/n/i5uSVwBiACidkWX5JWppkYRwEBH7ycGzxIZbAdLBsfLmi4xCYEVSETPocRdJixX4WcjnUiUkcRA9ThGBp3hghShHscvZx/K4M2NAhRDPMvwP/x",
        "XEAMn/wA7jERLjGyar1zz3n/15/+f95kcZJvz3qnr2k+fahUu7oEhN27d1y8X/4r8jIwa/H8Nc9ctZ8JzlL17U59Ja9ado6/vao3dhPvDonK+3XPPx3eZYZT",
        "lfPExQoWi4D/8VxADF/8AOwxEPZSSalGvnr9Mjv/+3VHAQEQ/+vUkgustrNyLwKQ7Hn1l7tmb0zxgQrpdn9vbrI1h55554Z1TqnOFzq9askhtbxVVPsl4SHl",
        "lYhhiVGnWJ7h9VVWKAFLgUoJW4D/8VxADH/8APAxBCAZUSxW61/Vzzz/6ev/v/vUrVKamVdc9XXr2wW0M8tddXV1db3n/3KvjWBHi88zF54nk44sZ3iRl3m8",
        "lic6zk11gqkNV4/lAwX5/nKVclZjKUvumlYSpBz/8VxAC9/8AOwxGUcBATFkAP//////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////zY0ENE6v+uZvP/29f/f/RUsXu1n2+ld8AhCN2P+9kHCksLd",
        "7AsDsk3q0+UDAYGBjy3itv/alr20Xivsjo2PwoZElMW6QmhuuveGAFNooQLo0BG3R0EAPgcQAAV01n4AAAAB4AAAgIAFIQAvv4kAAAABCfAAAAABQZrIwBdx",
        "F/gVAQaXpUy2DsDglfCKudgZ/1SivUceDuwlt+Lf3qZfN4nmXqtvg4X/jgkrrbZo2t8ntCVwfepG+DXvUifrt8CetqCCwMDWA+PEOigvNotwgsMcoITil1tw",
        "gqiZAsxDoh3/CCwOUYH10+ba+DZYugsC5UB3g5CXwRYj4sfx7tAfMIQJD18Gm73GnosPths+/BFHAQA/PQD/////////////////////////////////////",
        "///////////////////////////////////////////XBDj+B1gACAEDQABAHQl3xB3/Bwtq9Ug+KPXwx2n+8vCp/AJ+Od/nnQS9+KXZb75K/ieP+/UJaglp",
        "QguufT7n0+5OaoMa9WD+vWm0IEcHvF6h9oAhj3kkrF5ISQkEQR9aDUV9Lmv7iIE0/gI/xPYQXFzabfE+tX8b90dBADAHEAAFhmp+AAAAAeAAAICABSEAMQXZ",
        "AAAAAQnwAAAAAUGa2NAXcRwYfqmX8ILAphaoOLNcG/vdgLyBJqH3MsgCLnWAPn/Bn7OFp/AF/Vf0J5fUyEFL6mQDcgGmsgyAr7wgodpgEkwMtfbiuEtQJGCm",
        "wgbOX4nAGzlthrpAU1QbfBifX+Al/V1N64L1zn54GAaQDgYXFFiXcUsR2EeGDzQbqXcu/CSmweQMOm2/5f/gwUeQN1X0qYc2RwEAMTAA////////////////",
        "//////////////////////////////////////////////+kQGyz/UCh4Q3UDYvKskGSosHwcrGPAqBRedfWIvWoGbi+f1QCdTK1carDy1FfXGPwLW/qbXVz",
        "QJk1QQqmFxXX0/AvaHq4iSMsVi/zsp+WuT6+jvjI/WEI6Xwm/DDc/7PAkgYdDaifr688Bb8HXThBDsSIWxb/hBbExkxnMZMZ/qAEAJxC19RHQQAyBxAABZf+",
        "fgAAAAHgAACAgAUhADFMKQAAAAEJ8AAAAAFBmujgF3Lm++suDL4Ol/utBhW24eHQECteLCK38VUqc4PwYc4ey+pkwgsyDHLLvLvCG4JwTt9s+8v/6xD17rHC",
        "J9f/t+O84tTLMv/50g1/mfE3+RQHEC68Ga2GL+J/AjBI8kaDEO44JJXczf8CBUi8v/wfHhSeE8sUv8n2Y3+pEAvPqRXP8/1AqdeIQL/CIELiAExQMBESEEcB",
        "ADMnAP//////////////////////////////////////////////////V4ypwAry//q/gm0p4Q17uAkPg+iKg+6+vnz0Qs/C3oez74bvehCZF/PAsXX1q+PX",
        "kbWXS7l0u+PnwNnEQR8vLgwA6YxbYhfBnQW6akD3Owzk/G/9B4qAFKd875/O8tPY94aqGvXscPnsp3/PAWwbdz/H4feACAEl3P/O8T8kTAZK8Hl8HasUsGIF",
        "fXUSeH6gR0EANAcQAAWpkn4AAAAB4AAAgIAFIQAxknkAAAABCfAAAAABQZr48Bdy9KmSeWBEDytqvW3sHqyZe1bcoCtBiBu8ueAiAjwYlc4V3DXqIpFUILor",
        "VvjXeEKh2Kn3v3wisqKvzanb+sQA1NBsTzgS62rSP0ix+WPzP+CBZ64KVb4M6P4/aA6gAgJBOGfN3wYkz3BYeTwaKIC6c+olI4Z/nqT/AR/XAoAUAJy/6gf1",
        "C2BBbTGOX03wXqwz8R9HAQA1QQD/////////////////////////////////////////////////////////////////////////////////////S/47+BC6",
        "hFXOuv/PoSk/4p+MPQBfxLCuC7XgcePacJaTin9fLX2Gtf4MPg42f8GOvus8qEJr8WhSi/Z/EQS5/O9fXDnGwghzfqVFRPo75PqP/zhYxZdm353zw/nevvg8",
        "6hCT8fD1MfinFOIfELngnWfzvXy/cEdBATIBQAAAAcADNICABSEAL52b//FcQA1f/AE+MQAoayk40P/+8/arzf/4ev+/+kqRqrqb1U54qc6oPxf9GqXSZxbW",
        "HeX83ZyUHbS4sDScu7uHJDxExLlkQuKJSHhihkpLQirlqurYD0ddvHAtftas15Yqpu+vKd04TTTvB//xXEAL3/wA7jEYkoGBma4r9M3Pz/29/+//OkdZmpkq",
        "3NmaoQ7BPnxlRMTG3ZMPiP6E/TSQbI7NkdkbbI02RwEBE1pPs1ykjiaEVdnfZG+4NSkSRiUjUato94xrYlRFatOA//FcQAz//ADsMQggFjWQZqNOv61db/+n",
        "5/+f31UXe5z9Vi/z9SlQVCWGgEBHmk8Fl3F95dbi0OFcWEWrVDVqrqhqwY2oqVT5fpitWO00z9rqE+zNRLguSUvjoqFffhmQAQgmkjUGeP/xXEANH/wA7jER",
        "FkJAucb6/Sucf/H9//x/3iL49STOKr18ZrxxQzG+99ZhCQkJTQFHAQEUK/UxQzNgwAV/0523mxf9Ppr6N0CWWOucZSsOb1T82iSHEXvGGyaM7uN/5Qt010bS",
        "da4HWSgnXv/xXEAMv/wA7jEQ9lJhqe236Vec//t7//n+uJnxuRkqTK42QY8uV9GzvcWQqSjJQbm7/Z/T0owMqnnnnOo45polNYTtTHvBWietCUlVrcpE9Tjh",
        "qbOBSiRs1oh+XCuEI6TZuslw//FcQAwf/ADwMREuMlCxpf53zPf/8Pf/9P9qk0cBARU61XMmad7+N69/ahiZE/S7tt3te1d33VdVQqR55557vSlL2uTawkXS",
        "MzGMnkXrk7iQnfvHgJzT6w6qDac62jWaEisb8P/xXEAOn/wBPjEANrJqpf/8df/giv/29//x9rVrGpupcb0FAAjeetz7wAw0QdAxuSJ7kKtwhEBW/Yr3WIOW",
        "Hr+ur1POownUf+tdU6q/U4MF1z9Rw1Wlk4pIHVg2ybNSGhYgVOZrMXFa9EqqLCxarJtImV74RwEBNlsA////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////FcQAuf/ADyMREuMlCxxud7334/8fb/z/8otdEj",
        "F+OpPn2DGEXVuiwMDA34/51d9AZndFyL96XP33cmI72FpR3JlWu6ZNqWENQheEJqY+Ccp16ysLCbNVQGrhxHQQA2BxAABbsmfgAAAAHgAACAgAUhADHYyQAA",
        "AAEJ8AAAAAFBmwALuy//q36RkZfWja9LR9I3+gOQEFXOYJ+YDD/PARAR4MSucK7hfPEEkBueEbL4BVqYX/UZXhBcc9P4QWMUJ1+mnJ+Y3/XL8F98IKZdcHfH",
        "+fz+T+b4NPn1IjrPy3AYHfS+BuPA5yYpf/gQlHJL8LncQsZ+KX5PFOoR/UCM/XOfBb/iIblk88T1193oEzjWpEReH1b/PEcBADdrAP//////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//8/8GKtjFjv6/gx5vPP11Jzfn+u8GHO+f76O9HfrQeKgBX+eHeuzvnbmj/rQepzoIa/PDPX4MArn8752eIP1+f69V+IXqEUHv52H4qAR0EAOAcQAAXMun4A",
        "AAAB4AAAgIAFIQAzHxkAAAABCfAAAAABQZsQC7vAYM8yAm/gIlbIOv8BhT6Mq1EVw/1WgbLPaizcx4JFu5kIpZ/lCQF/EwXz+cFwHxDVB+i6GRhEc277j/1H",
        "k6y6iUjjCCzqKfpp+bVIpPk/9HY9A1V/1d0EgVrF0OrFj2YFRLSCgqcDmPJX/g3XiuWfOwAgOzKVW/mF3tlHh8T39cGnwI3Xk9Wv9cviVDFNRhHUOg5HAQA5",
        "MAD//////////////////////////////////////////////////////////////xwQHBPen5f4O/WIUt+Dnm8Qsv+XN54BIVpwanL8Doyy/jICcPEWgiNH",
        "/ihXqEVOONA+AlnSA38DrXerBJu7pk5fl88O53iqwRB536At4M550/B6pwgs67bf+TXuTjJ+Ry/LweKxOeH6E+I87xsmGg9e4SmgFxR8UfJ6FFJ/ngBRT/5P",
        "k1qLgEdBADoHEAAF3k5+AAAAAeAAAICABSEAM2VpAAAAAQnwAAAAAUGbIAu/zoycBL7jjH4S/jgr9TIq+eRGx08eAm3O9N/57Pxva/V1P8T8wQAw4mCmfHTg",
        "mEzEdlG5iTqC49/nO4yoJ/n1In6916X1bZeDALq7HZ+x8GOuBR8n5ScF3qDvFq9H8KTP8TtkWfn4N7sPAJFX2/nH5DWzwcXv7gEROOCHzDsOKL/+C/E+IeIr",
        "68QgZ+HwMVIuA79ARwEAO0cA/////////////////////////////////////////////////////////////////////////////////////////////9Q9",
        "QwVUzZ54GJj/AbmOzOT8nh/1c1wW8k3P9CUC3k8nv/6BY2LxRUYuf6gYevm5f4yC5XZ2CX9B4qCzZZs/WO3K25Bt3JW7k7DuI+biJNBgyCXRTvzZ68K5fxa4",
        "sW/oj5R5BU0mbwfeLxfP8/zcR9xHQQE3AUAAAAHAAzeAgAUhADGi1f/xXEAMv/wA6jEIIBlRPE6X+1Td//2vn/z/zp13GfHNS6v9PrWc8UG1ZwiYnCdDufmI",
        "+yfvuf32QjUdNFH6oMKFxmWaOg1cazULXanAx1nFbsRxNG5DRkhouKeenZyJhfS4iNuA//FcQAz//ADuMRk2Mlmtrjn85muf/w+3/l/pqXV01muba9dG9YDJ",
        "6MOoaAQUFKtEngXsLq8Xd5QAYIiJEURRRAiBREcBARhyQIkSXL7M8C1J0hkGPs8Edi69r7Npq20bn2E0KT07ph1OhTj/8VxADD/8AOwxEPZRsu8+cys/9Pf/",
        "z/XqpKu6m5avHV1zqAoc04EzQhIyVM5SvWbMEilgB4oIPXhRlwmjHh0/5OVsFJ9EWv4dpxlr22S6hqaNhFgwrrpftiMRqCY5l8fA//FcQAw//ADwMRkyMbL1",
        "Pnuq9f/tv/1/0saxecbvL+finj62DE1uZ2EyMmrpfW8N/6e/RwEBGfG8TC93u9vuaV/dguwX3/Jeu/3N6tvjaKzFCmcTvHnYXtelF1xlIT/BV1lI3Rf/8VxA",
        "DR/8AO4xEPRSeZ0u/2rnj1//Fv/9fJPNZqs1jW+fKsugu3gf2N27ddTXV/FgfnHX/YmdoB5LzwSHufnvY9rY93tov5XoTI2lIlRKQeuSMcNmGiThWVVDh32l",
        "HwjiowqcKa7Bfv/xXEAMv/wA7jEZFkJppcTX9l73/+3P/29rl5bW6uTJuW1HAQEa8bALaiWRtAyOLLdqnJAbkt0j3WIE4gCeedX6n9Z1HrjP4rnwClieglI2",
        "HwitXSMkDl1jEk07pTa0aDwa145DY4g4Dv/xXEAMP/wA8DERLkIwvcL/Nd98//H2/+f+slSXu98ZdT7fF39vihfVrH+p3QMWL1m+H+dXsoJHf++96RzSHpIm",
        "fmnOFSeetU+rGaoZ4cxNNjIQzX04DH+IocTCjyUURvz/8VxADn/8AT4xADayWq3//32/6UcBATtYAP//////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////1Jv/8Pz/5f41UrSuO9ZecbRFAAEUKSzQaUWIOcW3Q66cXY8",
        "FYpkfbK8oCX+unpFFdBjNGr6B1GMpqus0EiUtpEi9GLaQPlN0mQWSRuiFGqTayLnPrwq7UbFqStlJOhPR0EAPAcQAAXv4n4AAAAB4AAAgIAFIQAzq7kAAAAB",
        "CfAAAAABQZswC7/PAuQAggkZ2f1NRuJV4EvsN5x7fP54GxHQeHFvv/WrnerOXuK/CH/wjXsT8aC/JNngbIDu35tIHjDy++1f8+tVevcmrctq5oV/i9TIyhtv",
        "/49364AITXeuz/iIK8n5n/AyHBYdAEPxf4bnUceP3NCVohrs/O8UM1xHwZ5PacCDD4HHAgz6X8BD7m3/kgNFX5NUqshHAQA9JwD/////////////////////",
        "/////////////////////////////7gXDwhXBpb/4S/kIcG0DFIQCZqXiBM+Qw9O8WT5MCB/5NX9AJpc/2ff/GnoqNEIWp0EsgD8FZWOSiUa8/8Lqw1AtqgN",
        "z8V9v88ghEyPy2KAv+qEI3ePy3Xwllz06+BBW0kT4iHZTxdQhBtERXxHx0BgSH+37+7QKq71zjhDLEfEascdxEvLPqB1CBLURxAjkkdAABQAALANAAHBAAAA",
        "AfAAKrEEsv//////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////R1AAFAAC",
        "sBcAAcEAAOEA8AAb4QDwAA/hAfAAL0S5m///////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//9HQQA+B1AABgF2fgAAAAHgAACAgAUhADPyCQAAAAEJ8AAAAAFnQsAMphEEBOwEQAAAAwBAAAAFA8UKhGAAAAABaMhCMsgAAAABZYiCAo/oIrpRz49CtJx5",
        "YvkLe1SOJNJsBhYiKCA5fpc5w5shH5wtoVkBGpd0XWuW4vBNikRpBM0TOlDXD5st0Hc9fk5qUasjyLH1UHLN84js43zgpKWUqW5hrEROInmmjV4b6TskwN9K",
        "bdBN3JaRzC3QUkcBAB9m+Io9ANNAZJy1h1MbU2mo8vpgEp02LtHWvloiNBE7t5ovw2cOQznWsSZZFWh1PAF69ghgs4xPbuZCCJiLPx/sis32DtBNEVER30pR",
        "BAd1muT9/szHZwl55EVcRxOT+Gy1zeyjsC0I+lXlqATMWBEvkbiuorJeCaMg87fhsSYihPGjBFVZ4xAj4hNb4fBkeue5ieFxQZUVHoUAAQdY4AAg0RwACtzx",
        "kPAHLNhfAw4sDzVRTeKDUI4+RwEAEAynMhBS/CZu23nw94ICxShEjMZIDpcScQAAoAf4HmK5h5iuZ4XFcV///8aFFvv9xgLBwzlxx3KVcrJNzFrkT1dfp4te",
        "Y/6af1PwZFMxdQ+ufbbv8a6W+PXWnXMwiHkQdccud+Enf/f/OU9PUE8LwRAltB3v/8EUFZlDJ7M2vZ5wLAzUSaAwAYdb2h83gVfJ+9Mi+w0eqRkC/3YvryZE",
        "zP6oJ6/nuv/BcGl4eOBgHjU8SZqjNy/2sWhHAQARYHaYWEoItqsBIviDqWgTDU9hdTkf7f/ESkn02sL5b//b40kOxL5dbLCPl/rjQLesDDMF609PEEtyTCvX",
        "4BwVl4ngSEZwSwARrq+MFXAUmu9dn+3/+IeAQW2uEtEJa+B4iSx0CM9MLNL/7fwBXACAf6MsPzbGJwCQiZHiEz+XDM4uUBBqn4HuDFMHhmal4gTNQw8nph+u",
        "IxQA6SfvM4obzowp9aCOIYf/YKwlBg6DiAf0K7mS7mBxR0cBABJzDijubQZtYZgzAghU78bp//hQAPACB84AxPZByeNPubf//8Q8AgtpcKm34HRlljwMz28P",
        "8V+Gxa/FqGQCAKASAEH8BF62wAILurZDgHABD93OsGlDF0H2WA6RhDhBZMVsERLseVrQLlwUVMFy4/xu0OYSS9b5NGJtdnb/ADfvyLlwpwm/Qi4RMOft6REB",
        "9uLQmE9LUP08z3pnrp668A//2CI6riXGBnXUWgZB2mCXEBb4Ef0G84AQRwEAE5td5heBYGKSwM2FHi3sBIwwL4hTlqeDtPCuL8/xukUhTd59afc2D8AEDOqj",
        "OBlkhEIQqPt/EALDZbD2veLlBafwLMHRXbxIFg+4XUFfEunp/8GZDBPl0TvUENPT0y109ddPUTMwtNRsONCFoDAGnyaTcFKpxSrHAS+H9gsBnfEEUQS/PBHi",
        "gjFMGES0FWayf8AgerQneLJ5GD+TeEFw/DICqD2gctJ9PqCWnp4qCSBKgJSjfTliN9NHAQAUhYFPAugLpd2fYruzyxT1BXXTdcawXFaGc4HMeMS2bjEsyKwF",
        "aQg7DABu59PsAlQOpVcsnZYx2hLQgEqyaTeSZZx0U8yCXT37quWebdfsf/mgvFAMOJgH9rXT08VBNEuJeO94HU+4rgOgOqO+Hpd9MfUK109cUwVJAcZBixef",
        "T722FxUzDoh4kogbGw0kC2Gh/n0+6g1OWVXLCzFh9TL3+9/GGey0ukLIU9dQ3FQSQlNAExALHE2MU0cBADWaAP//////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////8KiQDokLHFfMwU9qWnrrp65mGBKoG4g0na09deAR0EANgcQAAYTCn4AAAAB4AAAgIAFIQA1",
        "OFkAAAABCfAAAAABQZocBd9Twl7A2QJ+wuP4ZpL/1tpFV3XrSgEBatKsGP53wqb/AFcb40XXl50BsgHEEnXu/h99/hDgkP6af+pk+p0ILUILKir+2zsEPEaQ",
        "c6DyAvCdXiNqRAc5cEZ6DIj+LcI0JSOBAEy9uDEpfw+vnOD/wY4tgt9m/h/sPhSKfhPEQsGMQgn4NvHyYMUHn8GPgxW3z6EtL8BHAQA3NwD/////////////",
        "///////////////////////////////////////////////////////////iZd4YDOeGZDvLBkBIlL/wf5wTUSS87p39efmfEYfhWQ7BLEYLPBh84JNCd/iX",
        "fwcrF9akH8CREBkZrfFW+P4oiZt8Veq8g9zYITQHMeTfDkb65cMARMQgT0PgmhTZAfPLAF1dqXrqREXqRES9iIJawP0w9B6RHUKVYefed5PFQEdBADgHEAAG",
        "JJ5+AAAAAeAAAICABSEANX6pAAAAAQnwAAAAAUGaKgFn4DAntwibmSGY5fgMGpVlxc3Aon8BH+Fdz6gb4QSOUuAwJ4zHbjc0P7+O//SjpYQ4oQE38X4RVxih",
        "Ov2y7GcPqMHqXlReA0PCM9h4pvm9SJhBGUSkEJEf8UPwZn0DOF+KXwBxago/b68RapgZQfVfOz9AIXa//PJwMd8f75+EsILIgkmVPBLvwBm1kFZ5/wfgxVvB",
        "RwEAOQoA////////////kC3difwbn3kWHi7/8EIEFUq6BviWGxXHw93a81P56B9/weniPoRBLl//4EAK6L80TF5wTX/DGm/g3WxhCWAUIBZ28GCK5/QPueCG",
        "b5uDg4eAJAyn8HR71/k9wLH89v4cST8DAOcC6rSecgFyAsiEJkpnECZKZXi1f/60kvqGc4HMZbofwlhEAgTBty8oqXm2XaH8S4hOLYt4kmRJM8Yv8oiCOqB+",
        "reQWl6T5rlhHQQE8AUAAAAHAAxmAgAUhADOoD//xXEALP/wA8DElg2ax81vPH/p6/9v+tk6yVU1TOek9/IWyM4lKUxMS7/6V9PBGurVq1VaoatWB9ZsDVD8z",
        "Lfs8MGpmZwed2hjhRjO/gQfUUNyUF+ZBbBbg//FcQAv//ADsMREWQbK4n6Vut//H5/9f8aJNMGqfn6uuesE66X6zhMl0yeSlbN6wG5MXlBBs2RijK2zY/lPQ",
        "s2Vt2iy5b+tR6p3ZAnGETkcBAR2Wt+b8ZI79gzlJ1HR0OsZc//FcQAw//ADoMRkWQlCxWr+e+Zn/9zx/9v8aGk2lWePOa9ecDs5lokpFnYmrxSwIIli5vK50",
        "AMf5c01T/yOOYhP2EIiqJClS/ovgqQ0pDRXurAmnLYhfINp+tqaEEUSc+P/xXEANX/wA5jElhPM7L8/3qb5//bx/+P7mpS53K4q/HBWsGUrY+O7GrXW/W1db",
        "tXyn/ubv8ppWh83nnvNn0N5wAedDbzgDRwEBHsliQlbzyUhi73TwQOX1+DsAYnajsdnXlHzcOHpVLEbomw2+//FcQAx//ADoMRk2MinFvzX8Vtv/6eP/3+2S",
        "JSpdS+V2xQGYwr522AZGRlfb+g0p2Kz/Ut9kazZPPPPOFT1krrVWjVI0kWtXZtOolZL3HAuLZYMbDfR2pbHmItWyiU0i+O/A//FcQAx//ADqMRk2MhjNxxP7",
        "7zM//s8//l++XVavLqVqs781PHFhiVM/493oAjI4OLNHAQEf0BA8/GTMJIOHX3vPadOpNXWnnhLXNav1M8KV/NL8jLXmNEsNy0l2HOW2CpABGSEK8P/xXEAM",
        "//wA7DEZNjGzq7/Pre+/+n/H/7/8XVatkkVHftlevgDi6yf+vL9YUFhYWLCtwLIc4nyghbb+3s7LR/ansaEX4NGz2Rtyey1r2SuitEwX/Lty2UbP0vRG64sV",
        "25FY1h0EL8D/8VxADD/8AOwxEPRJETRQvOP4TJ//a+f/P/Timt8Z50cBATB2AP//////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////7vNVnv8L50DVouXGXjJBb5H",
        "n6/8kB9+gkRd0SIopEIRcgk4wkVUz5IRF3BCXCQlIJrzKk4YRX8ssGI2E0DuQjfgR0EAOgcQAAY2Mn4AAAAB4AAAgIAFIQA1xPkAAAABCfAAAAABQZo7AVf5",
        "54s4S/nhEyMva9L56Af6HEMIQ4k0BwDD68UMUZfPEHRFLX1bpMiux94v8YjSp+oxWK+FUGSqMQs4+GjcG8CAP/iDDeoDTyeolI6hAhYJCHQh0Q6azu/CCSgw",
        "ko4qj78IEyTLzmRDqcfs86AwOf4k7wlgMflA5hgCA/ii9eB2hlvNiqHqn/iYf7gELi+C84Il8hpHAQA7BgD//////x2M/gv9Ax+DlW8/SwEbN8GPwKOJeI+q",
        "frqgsC9X+CBXrgx+DH7OWhAKkT8GKufDAfz8lrNXXZ4NaBglX6YHylrz4hZ/8AqyX3j1wmuVl/8BqTqvwe6ctf/rWMV+x+fgeWKEKvt9Hgh8GWkvApHDTcmp",
        "/4MlcfPEtCBdfi0lXwLi98J0P4QLOwVpwanc8kOP4DqUlc+F25/55E/BxOm/PACAEW/6PDfgyee7vVCpTrj/qEdBADwHEAAGR8Z+AAAAAeAAAICABSEANwtJ",
        "AAAAAQnwAAAAAUGaSQBZzbzWC6oV6CUmUnk3/nisrcPjj1/GQuM+DLU6FYT/oMSeQfRsCxoDgzWfLZbT4VT9GbzLKzFFiHZP0v9RAAEIgznhBVBQMGZtrpC/",
        "RPngIgcx/jfycFnkz8hoef48e6vgSA12mlNoVy+Gnvo/E8LfngLYMqX/+eBwNIEKNFlm3igD/ByfB/z0GXp7X7fgqBD8H/J4RwEAPR0A////////////////",
        "/////////////////////23/+b/7gAhNd92f8QwWyPwKFDiFf3f3yXAUKDlHHvVGK3qZO/wECBx3+fwzmfBiVwDzFc+ENfIeCG69p/3oPJ1vW/aqMoEveo+2",
        "vqAD/Bz8DLj5oikVYE1N9qgLa7VjnKeS8GFaB32vB7PA4ZgAtt18vBxSf+4RUap19a27zxKR0zfEUu9Vy/vyf6oHdvzlA/TFv/XLwLkX8VBHQQA+BxAABlla",
        "fgAAAAHgAACAgAUhADdRmQAAAAEJ8AAAAAFBmllAWcsqc42ERW2EYWNgGOYQTOfg1O5zwIpfqliTvj3TAPvi/kV+eIAAVCIQAJUOxNf+T7/9TqOTPA4MYo4l",
        "0UXwEypvLLq5qTgVLPD/XZ35M4eC1AW4mZ8VfJ54HOR0TRS/8fwlJ6J7/8Gf5+35KFp+CdedSeQn/49+c/t8sEXcA/8VfXF/qw4e96s+DFX+DFWN/Ax4l0cB",
        "AD8iAP///////////////////////////////////////////8QgT+EJwTIS1fg5b5fiuDFcuXXgC8IAW8/j+B1BACCXaZ5kPjyZ4FF/WKcJKmNoKaO3ilg5",
        "KnCCzoiKZKZyGSGeITwgoYyx0B+vi38GIJpNAuV/kURkIAovqIdCBOvS5ugIQKVfqEVzDJ/noBPxrvL/+e48sX3WGrvgfpi3/9QAv6PD9VAQ3wVIPOPAQXX1",
        "HqgLEfEwR0EAMAcQAAZq7n4AAAAB4AAAgIAFIQA3l+kAAAABCfAAAAABQZppgFnGcCD40CAcwAoQxeLJeKSHnfxNRXEoSIvzwPsA42e/Akt1Rk+Tc2eBxiKt",
        "4EyDbl/l/AQmJX56j+n/IP4GAA8cDgOb8m/H6guvxITIMVL28ISqDIKIClQay/AJeWZPgf8GKsPBruWT7gJrEw74QyerO4P0Hnl88iAX8d7/XqCLxBKBALfg",
        "olT/gpV64Meb5oH6JmBHAQAxWwD/////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////+2T1TqX/9X/Wgl+C9b/Bj1Aw5f//HBGh/CQuwGZlgJw/5fJ+v+rGWv/8Qn8EyRbOw/IlgxgwQYrkgbVInVnkX/E96AkVA7",
        "OPh3qBPo8Ly32e6uAvO4Fvx+K+b6r0dBATEBQAAAAcADMICABSEANa1H//FcQA1//ADwMRD2UkG51H7Vmuf/p8/+/76utVrJmt8b1uSsuhUI/CPu000x5VVl",
        "krYMuAGtQC8oCFFFCzGw16x1/fpYnGOkjk0ljHFN1to8/hPLV4q7cV+2y7RbSaFj7CY67Mb8WRGLqTj/8VxADD/8AOoxGTIycKF8Pzz3lf+n8f/f/e6q7okq",
        "1d9HfQIYMPrtxEyYWdn65/sXz+/q8DeWIhNUREUxRwEBEiJAEGhQmeIRRHOop0MStEedq0lJQ0XwwJactGI1r4EylqMFuP/xXEAMf/wA6jERDkQwwXrP2c3z",
        "//Sr/1/5sSXVRdV8/FvXtgEBHOeW23bv0nW7lq/5K+hIqEqVCUpW0Tk0vpKSfzKxm/KWTx17Hpw1m4CblrO75VzSL8qjKbb8J1lldjdFwP/xXEAMP/wA6jEZ",
        "FkJxoTjv7ZdeP/w+3/6/RGttZpbnnzVZxQgHG3zQZGBlfbrZ4wNHAQETg2Z2fZaEwGCeedUZ5x6qUDg6ynEU5PzsUJ7Vn6U5SGNS0ggBqbnVeEcNZbQLyUpw",
        "//FcQA6//AE+MQA2snKh//tv/tu3j/t9v/t+KSuKzW9LVvjLpQAHPpdg3mIaYayRqDfUJLCo0W8Scfhkg4df70vPPPPd4TpcuYNMgDNJIMlCGIlu76EtLagJ",
        "7Yxkxc3KgjMjAjVUSlaM+WE5pa4WSaUsJqRw//FcQAwf/ADuMRkyMnChxJ+mb0cBARS+f/p7//p/pczVJMks/P0nv5gJ0a7bltA4WFJYsdh9Fv8ZzCn6P00o",
        "xsDTnaNZOJzeorOtdF62p+hFcaXTuJuzfFecZxjcyChEBKxGvP/xXEAMH/wA6jEZMkJIsaT+G79f+n2/2/9uEuc8Sqy7rxq79eQKFQbasgQEWJclyn97/hsO",
        "/Eju7ou7uiKLueKIacSJi6oQVnCuqtb+msg0IC6fnWO2DGM4vBKFKD8zgP/xXEAMf/wA5jEZRwEBNV8A////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////zIyYaiT+k3rn/6fp/7/7WaZd1KSt6k5sLVS",
        "QtPGoBQUGjhRpj3z5y/gSEuiigwooMF0UYYGYv9KXQdF96KqROMRy2u1ko0rW2ttLdrTifiCjiqISWtDW4BHQQAyBxAABnyCfgAAAAHgAACAgAUhADfeOQAA",
        "AAEJ8AAAAAFBmnnAWcb54loRQ6nfxQ/n8AX8HXCOEvjyGUHBFhkZz7xQZJs4sBscCRR1z8K/+fjx/CwDAwFkB+oKJU/y7j6UCBELIkdFF/+Dv4NeeGOf5+b1",
        "kso/g5GUQdFL/l//+zzp/A7KQlYr4P+b54ApHEcnqgEsfwDgI8D2+5P88Bvyf36nC28NcW70S+wKACB8EAMfg759UwzsEEcBADNpAP//////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "yD4KIFEwJVK33m/H8B1KV3z/5INl18G1Ob6a/3/FeCY6msIaiLQHUB/CmX+wc/BOpkT4O+fuTuTo8P0IXr6zh5CtP4NEcv1Xq4CP9hLUR0EANAcQAAaOFn4A",
        "AAAB4AAAgIAFIQA5JIkAAAABCfAAAAABQZqIgBZxrvz0q/glHVp/nhU8Kmf5UPubrixL49mUS4dHi4N+h2HTBJz6+qEttz8ZeedBdf1IW+5B/AwA4GDODiiy",
        "7p+P+mWbir/PqA1zwliIKYj0Huk84oDgGmEE0KWbf9QMKmTS+eAI3E9/rPHYBPwH30foGK+fByrc3z/JAEgyvwKVc91494HUQJbcvX98/BjxHR2CHiNHAQA1",
        "WAD///////////////////////////////////////////////////////////////////////////////////////////////////////////////////9B",
        "brPCvP8+tN1Bh149h7I9WSHCm5l4MVrCXOgxhngxpf/Bavc2e7+B+v+UJAJSI/r5PEIGPegYHQBPlVzkgJtcsJYh40MFC/4RNz4eD+TzGr+BxVMj/MI++iel",
        "X+qRQEdBADYHEAAGn6p+AAAAAeAAAICABSEAOWrZAAAAAQnwAAAAAUGamJAWcaT+T/71Kgu53xYl8nyf+fwTfxPaLknMA7/Fc8I/zlyQT9vTDDaeQfwODGBu",
        "sUFiB3FtPP8R8SFgtGj6gYK8HU8ULEncVbcfqDIC5hdl//Bzov/g75/PBDiPiOUWw9OTl4R4QqEO2FyfEd7b7XpB71wAhe+7D/z9nYIcv/9/X49AigSIgJBJ",
        "bfFW+EFgUTAoLt60RwEAN1kA////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////+SD9X8EArTwFDq/epk1fno5P59PuI1in9QHQHfqQQCcT1fV/dqAIc6g4PIv+NPR1NUo4kGdUbwJxzov+J7+AkgiqVR72/h2PN9H",
        "hmhHxMAjPfl+Cz9Yvh/4M9foPNhHQQA4BxAABrE+fgAAAAHgAACAgAUhADmxKQAAAAEJ8AAAAAFBmqigFnJ6pUifiv/OT+bx8EOvVAar4sS/5y0HV/g6SmPY",
        "qeHYfwHVy3q1wh4WDLtu27btr7oTQuaFowewx5fXqTAhCzw25UfRCZr/o3zxkOId/+DFc+PegN/AmFOnn4njPPEyOgR16EZnf/x/CUnT+/15/v+ShkfwYAh0",
        "b1zfP+BwxFfE9epRKP1AaE5KvBjoIK6MH9P0CEcBADmAAP//////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////////8Aw/Bjz3z88V9BYDRiECWfgvQe",
        "r4K1MinPnoWP/Bh+5Pzf4/dQ9zfd8nqRZRf8Dd1pRtKCHVIoR0EBNgFAAAABwAMsgIAFIQA3soH/8VxADF/8APAxGRZCQbnDr9O9dv/p7/7/7amcCkuVP0/G",
        "XUAERFjt8CAUeZ5ll3F9hUWQXJZQAZERRAhyfiyqiKJc05IL9XhXQXreW2KZ8EChRhGzWiH5ezXs6haXBJCNuP/xXEAM//wA6DEhNjGzh1/XnnH/9vP/X+dV",
        "pVSrZ1Vc9VfrqgsQBJVOuuRLEEQRBa0oRH8gi6sPFBBrl0t444WuOuPTDG1HAQEXHY6JWTy45TtSbP2pE9jm7WlHhO9teuD3Dac69YoYgTtw//FcQAyf/ADk",
        "MREWQbK79v4rmc//Xf/4/qmV7VnWZd1XrrNevYAolF9GsvXuLIW8EdeNs/Q0owR92/fvp7l3ufhDfTfkW/M918X0z9a/hG818XMYEegLsAnMVI3jdGtIWboW",
        "4P/xXEAMv/wA7DEZEkGy3t/fNz9P/wr/8/1lXrd0XnFd9/dXj2oHBud3u7zIyMjtq3P+C0cBARh3uW619ctc56/Trzzf2OqsE80JelPHf88NazEhPP+RCv5b",
        "NGFSsJcBY9memY3RknW8+P/xXEAMv/wA6jEEIBY9jJQsedf17zt/8f2//j/eomqzWcc3M76levgJ79ff7EMjIyW72B0w7TfZT4gFXP69XVPPhOfqXgY551Lw",
        "0PcpbaXote/SQ9kdELC+ZgHa4qVFr72atLMf//FcQAx//ADuMRkyMnChd9f1zfPr/t6/9v+sSXi64yU9RwEBGXtU+fagZAj5dnUKLCwsLD3v+ar2KAyHO798",
        "orkox/ciO9LNIY8rEpU96b4t5IBLEPPnjJBXf4MyTBbULHB0EnMlB//xXEAL//wA6jERMjJItNP2rc7/+P0/8/9uFXVtc1rW6+fpN8UCk3ww9NNhpzTkfiPr",
        "L1GQl0dNHT0iOhaxhhR0txtehs8vllvMi62zsJxvosEWBcpiMR7qmxwUtRGv//FcQA1//ADuMRkWQnmdbz/Xdan/7ftHAQE6YwD/////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////////////3/v++ozomax",
        "cxJuAYmJJnsFAQUk0PmQi5mDLYBbXAuLAwiiiKKJAiQjiOQykFchFyAQT8QRClZ7+I+O7O3owpO+nvNOXBCt152/0LFNWhdCF8sZ8EdBADoHEAAGwtJ+AAAA",
        "AeAAAICABSEAOfd5AAAAAQnwAAAAAUGauLAWcdP/qgCqXixL/npv24HF2XVYBS4f5y8O2vm1Z/CiN9ZdQMOPeIIJCTWIHhLJGr4niQh7a8XyVpN8GS9XBivZ",
        "PMf/9f54dxH4QxFfEdecEgEqCCWz4tcI6gqwwY68m4oFsYtB7Xgx4nkL/+rLPD8/rQU0/gzQevrMH9RzfBitfBieZBR1vxVc2qUfBZ8GCtnh+eT5RwEAO6EA",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////7kSg+6Dj6wXB2Hj0AX8KPcn9+B+",
        "DvVHQQA8BxAABtRmfgAAAAHgAACAgAUhADs9yQAAAAEJ8AAAAAFBmsjAFnCM3FiX/OUohW1/A80jj2KgCIRIO/hXP0/qkjvPOgCfHMJSj/9UB0Jj+A1wJFOu",
        "fm3iPJ8hifwZKhcnHvACSSHXifWECD9QIABCDAfwyaf/uAmV8717J7bL/AdGT8pv/iuM88QkkQdFv/eo1TH8NdA7Fi3wdAjOEGXQrADBPg6PfwcqlWX5/ifE",
        "QVyROgXMVNHqgEcBAD1dAP//////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////cjReBRk9b9AUAKKt4IQIKmRV4ENc5zZ6Aj/ARFtLvI8mG7hLwC+27y/wISt0EAMCt1SoKotdy/Xr6Uiz0IWtcEWfSj/4Dc/k",
        "esFmBgHif8UVVgmBH+Cyr8V4R0EAPgcQAAbl+n4AAAAB4AAAgIAFIQA7hBkAAAABCfAAAAABQZrY0BVy58ZPxYl/FzxOJR+XXPlo95UIWP4mp/PTn8XjvWB1",
        "85joJ3+ES1+YfwhMiCWligvii4nz8Y9TwyCYIai/HwRVEgTPEhM8aP4GAGAgfHFFl3T/gzofwJBYLhtEJniBM8fwPWB5Yq+IEzxn0EFgYZx2j78I7YAoYWnw",
        "OmOX+M4CIQXdvBvU/xXNwYfBgvzPD8wthylHAQA/bwD/////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////34I/gx+DHJ40pf+ut8FEGGP4b8NG69MW+sGQPoMT+AD4ENKuf9n",
        "h2KL/gJroPFedWeRCEx/PwbfQlx8OMY8C0/AsBf834CQ1EdBATsBQAAAAcADLICABSEAObe7//FcQAzf/ADuMQQgFj2MnGh7Z885W//j9v/t+OpvUvdXdaze",
        "a1W5BFvs0gEgs7STdxXrO3DJYAeKAhQa/WZe5a4M6UrCy3CiBgoHh4sbeSFuIOWpgstxoUgLZc2lHwjiRqoM8mGv//FcQAzf/ADsMRz2Ukm1xn3/6MzP/71/",
        "/f95JvVa48aqVPf2TvUDC9tVofjKuryFRIYUCl9fQ+XnRgbnnV8jq4qERwEBHCR1cdiuwv05DtlmnfYXvmpLTFOqawX3a82tioPBVLiU+FLIcP/xXEAMf/wA",
        "7jEZLjJgqcXf9M3vv/+3v/9/80txzJURXPWa9/bARKNm6zcZGRkZHa39hX+DKyvNjzzzzHk97EsreSg1DMUsdZ3SnNWU1vx6j2MPK0JJzdU0/+Ch/Sd8IFE7",
        "cP/xXEAMv/wA6jEZNjJxodL/tXN+//T8//j/nDiqi8uTfjqOeKBAOa65/kQEZHbYXMNHAQEdkTPLPCRzAZPPPPOr1E8/RzTnnGAOxYBP/qc8j8dTLJ2GFCkU",
        "jeUvJ22lUd8U2iGWckpQcP/xXEAMP/wA7jERLjJgqa5v1vffP/p8//f/mJFZquN6x9vxV/PxQGpxYHGLFi+Jvh/jV+VAaTu73O/997Hu9jzEjF4mA0iEXYvf",
        "6YBOXYTx94cIOs7oTJegUN04aoEQvPj/8VxADL/8AOYxHYThQqvr+2beP/w/b/3/9olcY16+N3VeOkcBAR679/IZzmzrvvkIROGehnqP4Pku9kLp6f1R0dBl",
        "A9fQeOjpMAuD3aMesxzGWqgRGiS5ktabDF+HumM52ncVlWlM6vD/8VxADF/8AOwxJaTDS4uv2xT/+1+f/f/fStSklLy8QqxdYzHf7NqYmJ2beB18+x+pPpYJ",
        "EUURRAgSOTJoiFrFEhK0E4nlohoyntyepoRoTcmkE4LdtyM3+gT4yME01LbN+P/xXEANH/wA5jEZFkJxoOM/TJmfRwEBP2MA////////////////////////",
        "///////////////////////////////////////////////////////////////////////////////////////////////////////////6f1/+f9qlTW+M",
        "hcz7fWq3YMjDdq8NTAjtJNqVnaV+J2AN3ovKDmXQai9ZtZtdFAddCzCc6QK7VrNRaqNftLCiOI0bW2q4hqqyj5uCVIGKU8VpIy5HQQAwBxAABveOfgAAAAHg",
        "AACAgAUhADvKaQAAAAEJ8AAAAAFBmujgFXCM/FiXqf747j1jHqoDojiYfMXAiDUgUPtg2dwolcxDATgJ+e87AOAf4WZfBty4/lXyZl+VuXiBngU7gOG6ga+K",
        "+O87Fl9rA9cVQ7Va7da98HalSjvx3z+eE+L5V8GiDzuwOQCAV9twhCB/Bkvn3Lu+V3WulGLegIx66/08+pU14GIOHtwjaxiaz+r9TJ8HC1+o1UcBADGIAP//",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////2fasU3/+W9Ui+qAT4EtX8BoJRIDgg4QUuAYWCAN8JF2IxHsbMWG2VSeuv1cZuSA",
        "R0EAMgcQAAcJIn4AAAAB4AAAgIAFIQA9ELkAAAABCfAAAAABQZr48BVxnoN9CAl6ivwxjgjBEgioPBxRaebihaigvSnlQRneDyq2VX389J8e7UdlHrA80BTR",
        "I/ivj/GRJ/F+JZBbAQPMNeET4Im1G8BBCZMR67pDwTxtePYcoB+XeBNR9zwYdwE2vu9Sq79tfETRZxWAhRH+ewdEZ+qGAYLrwUVjjQIgMCtV6sd6nT4HA/v8",
        "JWH16X5yoQVHAQAzZQD/////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////2f4PHvJ5v/8/j+gI/wrl8IAwPAYuBxal//Bhk+aoLvpQTvgyOrv4maQUv/BdBJ0CPk9C//quT1l+mhBZm4ESqRQg",
        "oroIBP6Zd4HAEaiLQ+5+WEdBADQHEAAHGrZ+AAAAAeAAAICABSEAPVcJAAAAAQnwAAAAAUGbAAq43COEPPznK478jzoMsBCThBGgcYgOyxRfbnEsEPjZw8VB",
        "pa+ITSl186iOR4qoFd+rj3oDf1lm8f5Iwafp4t8fX1xHrlCEwZA0938GHUDAvuoGNXOvjvOzplsIfzmXhHucPR17BcplmEuG/DYGvm3hHxDBMP8ULEd8RARC",
        "iLS6191qOOOte6111nt/h/AWutgw9Aw+RwEANYYA////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////5auPgtO3+KL5L+b+DLVeoSk",
        "YSROr86Qptf4oWwhtFQGFr8+1NngOoE4755/x/v/WU1HQQA2BxAAByxKfgAAAAHgAACAgAUhAD2dWQAAAAEJ8AAAAAFBmxAKuOrnEIO+CWg16PJ+x3+kEF3Y",
        "JSYjs937xROTza/z3/g8qzy8QEniKj8054OEM7MLA8H9ciLE0f54biAhDnOVvFxXvg6kk+Tn58esRSAR7ebcn44fgMCB86xz4OFah/Aa4EinXP/CHNGfhQGG",
        "vBRXvIDJSKPg6U6Zf/1GFEXtRorrAoeoGdeP61GKdalTr6z0A/8CakcBADd3AP//////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////////////99z6oDfApK/hzaqwyOUzla",
        "B6rSX9fX8GR4PMBxF+2whPY+Y3HGE2IW+Kv8CqrCPyfgC/kaXpv6p3w7VufxCBbPR0EBMAFAAAABwAMjgIAFIQA7vPX/8VxADL/8APIxGS4yMMGuOP4znvn/",
        "+3v/5/68ZLVMuc+cnjqV69gBDCu/upcyZ2dnpa339+zgMjLlyj5bKinLzlFYccHdSpk1eCNble35QNFc2Ak9ns50QhXONpO3LMpKFCnqv//xXEAMf/wA6DEY",
        "joJItcZP2znuv/6vH/2/6rVfPHHcXrxz7Svn4BicjwprXV1dXXSv4FeokU888899Pol7zeYk8DFHAQERwzukzo1z6w0YzoGB7Oetsy31RwkrBU8U5i0u2Olo",
        "W4D/8VxAC7/8AOoxGRJBcaHFX+2+X5/+j/8f8FEtL3dVC/XUBxdZGfLMjIyMr7pzvgd/hbpPfv33pvUXb2/ne0aUo3+Ub6Xbys5aUbfaIxDWvVsRw2qLF5bF",
        "SQZtPJz/8VxADJ/8AOgxJYRxevqv43vxn/19//3f6VLrjN6paPHV78eYKVn1Hh+dy4zq8M6vDluz8dX6Ngdbz0cBARJ36WMQ9+03aSka5pylJu6M855U5U9f",
        "YexCMn5Zc+GcRWQqRJr516UTt//xXEANv/wA7jEthPM7286/8VvX6f8fp/9v8WNVJeawyG9UDCmRrU6N/8WAIOIOInYB0BW4M0m8BPgBDo6f011YNBX6rMOh",
        "XVhg3+lDNXTR0nI3qv1UeCMX6OUeCQ07bU0qtCx9hO2XInGT5Dj/8VxADH/8AOoxITJCYKXGp/THPP/T/X/7f7aCTXfCOfX1RwEBE6zvoDqEcGeRPAcxzFmL",
        "A3P/L8k9+gkRfuIhFEhEgKZHdCQGXSImLkUyvpCkhNmhnYteO+DoFctGI/K0PeUNdEcf//FcQAu//ADwMREuMlitqa/O+ea/9P7f/f/yiTVL563rL9+o9eQw",
        "GW/+0000yWPye0fckKiig1FBmzUUeBqKI9xgt3oo2J3tOy1suSlBoIxFazsX5XGU2gk7KZYu//FcQAy//ADmMRk2MoiVXWv6885P/4u//f9HAQE0bAD/////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////8XKubvNcbus8fWV35oEThX8K/gRigs7YfcJ6+PF5zOlgYcSRERKQjKCxOEGTV+k8HSnmpZDOIRgggBDa3vcrJzRTKDEe9iinYUQr0dB",
        "ADgHEAAHPd5+AAAAAeAAAICABSEAPeOpAAAAAQnwAAAAAUGbIAq46+bD2Eb1tl+CH9RKkn85oiZe2IHSvIyLu0e+IVP0+bB9Ly803E+fwWvwRLem+P9dOOoH",
        "H4MvgwVyRzfzcmENefwPn/Bcw968DgYWP4ikBZD8T0UL/gl7u94woEUvVEpZ+fgw8wMPgw5QDjVEmnwYL3JBmehIHR/LoougssCCrnYDQBdVQM6+6+fx70y/",
        "CR+N2/g0RwEAOYAA////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////10z8CIqA48d86uKg3WmqP1aStWOtTp2COow2EVbGDCSIH/CPcFQySPW",
        "OMD0D/Gyp0QJ2hz/PxFHQQA6BxAAB09yfgAAAAHgAACAgAUhAD8p+QAAAAEJ8AAAAAFBmzAKuaK4iTj8TPwmYKwYQ34m9SJPx54oREUy+sv8IcKrpR5K8DPx",
        "/Sr8L+xw/nYbGv2YMRM/BkrdgcAEAt9twhCCoipI/zwvYiEe8OBrhvy8Ak76E/h4GHwIC2+DJSJ+cdTvz7ufyelgIL+tOt+3hDl8/QHfEu9cCB+ex8blGfuP",
        "4UnIdcIXtz/+sRUbCwkTBTBZXt/cBEcBADtmAP//////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////KeJaKP4M+ZI/zQf3wd8/8GC98Hy/EepuFZDKk/B33zAev6p19U64e8YCnxcGa242BK8l",
        "c55d+vmv1blgMFQ27J9M3+uXPnoUovFCxHfF/PxUR0AAFQAAsA0AAcEAAAAB8AAqsQSy////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////9HUAAVAAKwFwABwQAA4QDwABvhAPAAD+EB8AAvRLmb////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////0dBADwHUAAHYQZ+AAAAAeAAAICABSEAP3BJAAAAAQnwAAAAAWdCwAymEQQE",
        "7ARAAAADAEAAAAUDxQqEYAAAAAFoyEIyyAAAAAFliIEAk/qIuoMCWpxWXC9LOl2ojZpqFkUdIJqSWkkS5BgAoEAAEp5VUYaisgEeUh8SqWRlcpRE4jwpmqic",
        "CX6+5fwJr1/C2UDH+uomOdy5+hkTc2X72s1Op2jnEJv7Rvu7unY0OIpHE0e6M6hD5akzxIFiRwEAHU7SbCCbX4X/4GS5a0uF05YTAJTrYu0yfsRGYikqwsyl",
        "835sJte3TFtFkE8ZtdCjBJJTklIs+IxEcwdNlQLhVaJzysGY01MNeeRHilFq56CDJnm/fuOwWBMiyINP2CXfIjN+IzFyD9vwVqb4hB0P+9Vc+5ieFxWVRPig",
        "ACBnHAAEEKOAA3xkLB2mFiAtrWIFiIFg8WvH//wrw6K6rwkLFA5jwEt8VnMzuYnALNwZKDVUB5xAACwA/4FHAQAe4yXMPGS5vV+AhjhD8ND77+NAxjfeUlcy",
        "krm0GS2LQSDtM4hP/EliJLB1/x//OyDgrhv1cY/AP1+IYBZDgn5zn8qurNGUA/djDRFZNhtYOsEnf/f/PTBLT1zP6nimCQNKYDCQMEeQ99wExprrYTvs4cuB",
        "/3BfNzq9PNDfqQvCHAP+CsLamwPHAwDRnNuJM1Rm5f7WLQwO0yQlBF6wCLvi7UtAmDqfOtfvjtD4aPdprWB6MGAYhqW5y0cBAB+cIevlZ3PC3j/grv+iHpU/",
        "/ph2nrp6eMggM4S0DgF0EGh7Xm++89pth4gXaau5sIWSoGT6kRgnpghriKerTmZv6ZxTfT24oGunrp6eMh6DA2BoHq7v4FP7VvaMP8GFTQFBCUwfXBpKnz3L",
        "ovCz//+mgH5d4E1H3BRIK3LZCh99s+pplwzIdM5aglrp6eunp66eoTcUwwOpmWx2O9xSD3gcDH/A8xSx0EZF4youhIof+TgIaKueLw5eRwEAEFAMCGmWvD8W",
        "W9f4/j88eJiu/XVoTIDFBCBY5tECx8BD2UOGzB1lxOgkJC6floRkDyFLUEddPT108zCLmoqDKgI9vgxUuH/EL7BdNnA4AGDgcMfAGF+gpPINFXMuyaF6CZqO",
        "3t/8CyYFRhHuGYaw/CPcMzWH83G/H+gV5sXAw6AzMbudnJnlc+lMT4zTGKEElpJ8G3LOTIzaAYgwACGX+N8Am7PHeF8J1Ufb/8OgcDABIC08JHuwfdJHAQAR",
        "kl3ff/8FY/WGm0Ejp/BBrz+IQ8XMuomunioIoVmQUxtG+8b7itsJSYB13fXd4oLFZocWV4Nu5m78xqvQaP6ZNxdCXBlAdN9Pwbcv//fh3cVy5wMAAToYDPf4",
        "Aza8Ozxu7PHZaz6FyMMst09P/i8AchJ+Gj2HHjPjR7COP7jAzKXYK1Lj2B6CA8YEPdk1M90UHEERNAzSBxbCQ3mfT64HQJlcsqnLGbQGNgYA75NT+aFXOSGW",
        "KeZBLkcBABKx5dopAmv3A+ZgrNzR6lioIoB3RiHfFcycVfxfiIC2vAmRO3avjJjcCCMKFSR3uQmOWq7xuoFrDAOLUd9f2EjsUT9R8KTwVkWOAB/7Sasbxqq5",
        "9s+54IQPEzIBwQgsRhTGg4ABe8cKOAApYnB4wBxOBxh7R41g1GKgxxQMJrH5a5efQuqZ9JG6QO8NDvPrbQkihm4NXLzyzOH1MJPTBXXFQVKBQARB3qDcvjHh",
        "lv8ff4okO0zISgReRwEAM3sA////////////////////////////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////+wIUyLtUtAmBfOgOACYH8iQpfxCBKKMTLIWY4B22mXv97/x1NCaE9x",
        "Xa3CtPXOwoA4LOyY00fva09M9eBHQQA0BxAAB3KafgAAAAHgAACAgAUhAD+2mQAAAAEJ8AAAAAFBmhwFnMX/F9Z03Qd6IGL/dUHgAoJevLx06OgJv4eJdfj8",
        "0Qt4UXfywS2+DBQGvBgrRJ2DN/ODJeEe5wj3ODDwXYQy8C1BiJ/yb4Mh6gEnQnnpV/FvYMPBh1ofxOgNNfB56nHgzHfPIgIrx7H8BMZeeApCBuN+KLx6tg4T",
        "gc9U6/wZK/1veBqP6E78+P//xZ4wofbUW0224UcBADVfAP//////////////////////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////9v4R4b8JB9P36feDP550Iv4jWfbwZYS4na23/H8qCFDb+BIOlPI9YHPgwQv88QhQr1CpID",
        "u1gZMQtHQI8fBIXDwZN7fcUfAS3QN1aTnhSZmWTX9wEtiZ8kR0EBNQFAAAABwAM1gIAFIQA9wi3/8VxADT/8AOgxGRZCeZ3Fdf2pm//71/+/+gurmtt6Pt8S",
        "93QgVuu3XfkCN2rp7mKOQcuTAKXUB4oCHm9e8lIgYmXcHjfVgVbrXiGMSk1Cwi9MoohwhS08k3TrUtN37cFK1mte0diWQ4D/8VxADB/8AOoxGJKBs1qf0zmq",
        "/+nz/+P7xHVd9b1mqrni85vQJ2a3s3+5V1dXu39s/Hvve/7XjRv379+/fRtHAQEW8m+mCimyB1aMS6k+drQbZdh7F4EmHRPsFplCKIQWsw34//FcQA1//ADo",
        "MSWE40Ovb5/jJW//4vX/4/zS84G+Fsy5N3gznLHsPuOzj0q619Tl8jxb6H/FbvxWFut5554J0vB5xKXkI7wHNrAYeYzPJuXytRtxPJ8LHsoNz1euX28Kh4cK",
        "Tru6IScYg4D/8VxADJ/8AO4xGTIxs6ef9a33z/6fn/8/96kLvlrelfP3T5+MBHdU+n/f6EcBARcElIyUrHpHjb+S5kFPL5fL5Y79/lUp5tjfE/Bote+S+zC2",
        "G3bITYIlLxgjz9i2cUPrTfdepUvbgP/xXEAMv/wA7jEZNjJ4ncXP03zuf/2s/7/7aqV1KVXGSvHFz5+IAQEsn4bAgYGFiXvB1/ThNTFABhy/ZXJiiKTHviQx",
        "BMR5pJGIYggSPO5DMixohHjVImVV1BnPffCTlxupnnLg//FcQAx//ADsMRkSQbOrfp4y/n/t9v+//W5URwEBGLlzcTevXtl+/kAZace3jKhoKDRVMR7R99n4",
        "iSC2zZs2bNmzRbep3j6bI0j+3Jds9WxZTjTmME+MBHYv+ttZvG03uopGlls0+P/xXEAOP/wBPjEANrQJOU7//d1/4y2f/T9P/b/eiXWWtqt+/1CoAA5VWqed",
        "iiyizp5VcThnouxgUGIXvdcWHZSxRRRBByqiiQRIQSJ3ytIn8JxEXmoPpiApKFkE5LYEgaqV1lao+ib3WVrAIqsFqINHAQE5WgD/////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////1z/8VxAC5/8AO4xGS4yQLnS",
        "/4rfPP/17/9v+eEkN8Vvg76T7fABDSNdi5kbs7O1bqf+ld5IQo3bm6DO0Pc9DOcy0XfpFYtOd7eNJJE9k44Tou6OyDgLGxQSjIbM/EdBADYHEAAHhC5+AAAA",
        "AeAAAICABSEAP/zpAAAAAQnwAAAAAUGaKgFnP55k8Ox+aCeKHzBsdkBwAzrnB/5k+fjAatj/hCVYFFQW/n0KbL8JH4RIdsDPPX6wjzZxleEkhwi4L3lBWyCA",
        "NHzfbB44eMBg4wGA9Mf+CPV8HL//3wQAyZPz+CT4OFrCPyGhnXjHzx432gXlwFkKyAydcY3KP4VtBTZc+8LsuPWEpMJSfT8Wo98A3T/N+AmATlbhRwEANxMA",
        "////////////////////////wSV+JXVj+IdBQAlJ4Tvz2anL+GcCeGQJuPeHbhZ/lfDj2TzzJy638f2/B0JisfuCjDk0ITPiBM/hBYVrjECZ6fHuTmGGt0I4",
        "g6eBSVIsHzdBliEDPoDHQMkKbLIBiK3famdfB0vYReKfzan+gaF/j/oHE2nphrJ5tjyYOcAoNiZkal8STIMVL/nr9B99CII+74HzvtDqteAyPQCJqVKwEtr4",
        "n6hHQQA4BxAAB5XCfgAAAAHgAACAgAUhAEFDOQAAAAEJ8AAAAAFBmjsBZzk/X8BYV4BmqwL88BrgyVz8fWvQt5zaF3fogYOkw2w2PoL3+9/6aE0KHg/gw+DJ",
        "BpyfAQG69fBdj/wzH64JopYML5xVQmsGXpsIgK6C9Ucz4X3wYegXWX/9WwjzQpsn/+MPTvwcXD8wF6UesCQUAyMlvirG+4/G8wkiYReQq+KL+oGxX/V5KgO/",
        "Hq0ITQgBKsm8HkcBADk4AP////////////////////////////////////////////////////////////////////////+0KZcW/bHvE6Crf6d+eIJJxVt/",
        "P4/gwwEJXb4mZ/n0IkReOhGf8lV7wKvBDVfVcDR8ClRPb/g15K6qBmXsX+/PwETI/hsyvH8DPAYXCZnnkz4/gUFwlBFiZniSZ/ngBACLf/8vA+X9XAT9+eAs",
        "JTUW+KXwhzoB0W+JJnr5Ps73R0EAOgcQAAenVn4AAAAB4AAAgIAFIQBBiYkAAAABCfAAAAABQZpJAFnPf4MQQK3gQP/hH/GXz2FsT8vSvk/r4MIHT2D5XO4C",
        "cP4LnhK2HxB+sChXu4H5aye//rIV3wUV3y/+CKs2T7/9Ui+egB8CteHyD+UQD8LMvg25cf35My/K3L1wfdwEAtGK3qOfXDmEd4BlAl4PBmfHoiSFabJ8HFQB",
        "s7nvhDlHvQra/hUHozgHCdUeoONxAAngH/lHAQA7TQD/////////////////////////////////////////////////////////////////////////////",
        "////////////////////////9+DwEitVupEdLA8gRqJ78BF/4lgjeLYcidBU26gZlKnWveDCrGEORAOiEzxJM/WqATwZgjVAdQhfAwc8Ny/SXgUOvrOHiIB3",
        "2wcTpvzwP0xb/IeCGX6P51ofD3ACPT5Nj/3T5NiBCD9fUEdBAToBQAAAAcADJICABSEAP8dn//FcQAzf/ADkMRAgGVEcXpx/TfOeP/7Nf/j/omlXv28XWpv1",
        "7J7+wBO/ldD3ZV1dXle5rfd7+P4hjzqnnnn+U+yf5KovtU003xurpEfHpYvNEYKYNdVlZoEtFRU1ITjelIUpaFeA//FcQAw//ADwMR2DZ11P475v9v/2z/93",
        "7pSNVxmXTx7L9+oKu9Pk/H9bq6urq92+rdP2q7qrXlr165Nc5zTmnOv5RwEBG0PBjnr9IrPM1lUhOccCaenXNKOC1RYzM4lNGv6fK/D/8VxADJ/8AOwxCFQi",
        "JZCcKHHWv+M5rn/6b//H9ROu9UWne/NPHsB609gqdB6zz+o6gEceis5lAnEAdXr+upeHVGvqjUPuoKhOOues5rcBRW+wylA9j63BoQF6DEb0S6nHLRO///Fc",
        "QAw//ADuMREOQki1OvXit9+v/T3/9//aLzjcvfEpPfyv59qFSoHgcdUDFrdX+dXfQGdHAQEcO6T9vRXEzv/dzGDliY2qdoatcdc08avPmME4fCBWrVXNzvyD",
        "KZ1oI0IJZnD/8VxADJ/8AOoxCCAYRIhs83+3fN1//Z+3/z/jUaqd+edSpXPnJ64sVn0LdoNxzHMWRHqDeB9Zv8x2kGz9tkbLbNm/9ttG3wxWbdFmyN7ZPLPY",
        "pXmJx/ltuowwQCwxHZECpe3A//FcQA1//ADqMRk2Mnmd5X+3iVX/8X5/+f50l67+OZlXJy4bgANezUcBAR20/16xQUGirjq+Bebt7ld7riwMERRRRI74kcSH",
        "EossVTpEIhEoitDAlWOMT1akIQa+nTVx3m30V1/BtXTXmna/CZYu//FcQAv//ADuMRkuMbOuL/u55z/+3z/7f+VzNTKdVUnPPxT5+qEE70/nH7GKCjs7VuT/",
        "orvJILbLbLWjht6pspbdjv+22VGxa0J8YqSC8fwXSYYoJmcUPuhNOhayE+D/8VxADF/8AOwxGTIyMMHxk/bfNb/+RwEBPmsA////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////57/",
        "/P+bzjLq9eNVqP09rv8/WAglslxXWTEZM9Nfufdv7Pf43iNw/KdSubj8jqfu/m1SL13uzVW+68PJeu2ERM7BbAkf98QSCwkgUOBHQQA8BxAAB7jqfgAAAAHg",
        "AACAgAUhAEHP2QAAAAEJ8AAAAAFBmllAWcRgxBB4ED/4R/xknNUDx+egH/gBN98R4eDCIrquvOZEJr8GJSztZf/AmAuVKugYK356P/+HGfiLAQHH+gI8u8GJ",
        "S7wfYQ6CAPuqyfr/q5i8ayGsMCPoxPIL4VmgiZl4MNf/Bct/hBafw+7G8pFSjZxjPhLbL6mTHzSoGV+B7Luh78hKT/il1L9SQGDyd14t9fqRAEcBAD1bAP//",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////xfB",
        "tj9YgUT+OdLOElTEZHTbe4z+89A2vBkpf/nxAJ+IBM8ILQPy9xS/gxBnR2COqu/OCIaoa/Eaz7fDX59AJ+Nd9Z5EEtvyxfdYau+B+mKX+I+/s75375xCBLJA",
        "R0EAPgcQAAfKfn4AAAAB4AAAgIAFIQBDFikAAAABCfAAAAABQZppgFnEBCYNKYFY0eIB/mripfvl4MPgw+DBeiL+/H9eEe5wj3PBlj5aGSD/BiUv8KAqOjri",
        "i/8RYXW9wJ38+gfP9MW/BhIvBVPJBhJ/FP4cqhPI9Z6IAkX4oLFBXBsHlc+DJX/WlRR+4qQU9fCm54/cAIVJHhw6Z3Pk9RAWX+pLHrBAwKn/CPcj30Ilv88J",
        "nJ/QP/wFyqBHAQA/aQD/////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////xMn6X/4ETLWrY1ht260HCIAL4MF7m1InWegE/JffJ4Q4iogliEzxAmeT7bgJgGK/wInPBH4Q4j6q3+g9zi/",
        "xEPy15+j3Kfr7r67PyiFkkdBADAHEAAH3BJ+AAAAAeAAAICABSEAQ1x5AAAAAQnwAAAAAUGaecBdxEvJhLdhbhGqFH2/CR+GgA2wEHh2QfDlMP8CR6nnpdA+",
        "fg28LF/UuROCAGGvDy6galplH74CQ4fqEG5/6BsGdX5IgcV/98OTcCB1A2Kx4e3XWMqgO3j/KP5UUfg6Exx6m4wGGii8JAG2BKLP9gK6rNpQRavWD8d1AuVO",
        "wIOEeNWEjPl4oYo+2xgFoGeS4CWUdv1iRwEAMXcA////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////8n83+qdQhwJAWDAf8VeCppPyeQ04C5/4t82/5L6O/ep",
        "EAF3r3P7P+3L6ppBEEMj/UHLpb0HkALk4k8PyyfJxkBHQQAyBxAAB+2mfgAAAAHgAACAgAUhAEOiyQAAAAEJ8AAAAAFBmoiAF3E4Q/3j/iqlR/gw/VyJ9QCQ",
        "lNIe1QEf4tx6vkDgYX8LWbL7rAPNaIBmXjcVwYdDgMHSrXWqRx+WRiIkuvBUGyDVqBFNcD8tEE1lg7+Ol89Azr8JH4aA9hXwZfBgt/1eXHVKhX+e74RrY/IP",
        "4ik4q2/Xn8JTvhNGXePH6jsQA5/+Ee4ZhrAiOv8Ia89AJ+DFXPH8C0cBADNoAP//////////////////////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////8YRW+2D5agalOmeXn17m+bPcfwrl1Ef4Y54dzvfBnn",
        "fk0HiIALiOp9Wse8m/rR4fzvRfgp3zAie9v9emJ/N/rrm+bo8Ec5+WcBLcZVu+LgR0EBPwFAAAABwAMqgIAFIQBBzKH/8VxADN/8AOwxIJKCeJ1+2v+M5m//",
        "p8//j/il11UZKL8dJ680FhEeVu7jqrq6utXW7V+O/eN32jKykpeeY8x5nem5PwTMppBpYHQZjA2hwJw1JgbHUIR73zayV7yUP4SnggFSNeD/8VxADP/8AOIx",
        "IJKCcaF3f+uc36/+Pn/8/xF04KWvfji5zxQGIsWnwR+BdXV1v1L5z8c+87/znXow88855/XA6lVHAQEQfQtQ9QZGFZ1LL1Nh+DP7LJBhRhZVbFIvz9kPDO0a",
        "0kMyCUYS4P/xXEAMP/wA7DEZLjJYrea6/vm+ef/7z/8f+uRJbc1zwfn75r38gRu57PH9jgCODhbmf31flQdf7e7+8kvSfvvZFFpYHi7mSXXVGpseCFfnz+on",
        "PiCM2ZI4DadCJItNgvz/8VxADN/8AOYxKIhLISxW66f65vef/26/6/95Ku6axnEr36X480DzwyLPzXk94pBgYEcBARFh9gBo8NHq0sAI3R+umugCs5h0110G",
        "aN9IDullMjJQtfmNlNH62C6y/ScRnKGRPaSp+Mbc//FcQAwf/ADyMREOUlCt1qvtvvfH/9r9P/f/rc1UmaKlPH33PXQYgf4re1Syy83Dd/7J92CRFFEhBIi5",
        "IEURIOjsZ7FFuVqedWCfWQwT+CcS+iebr1hqzjaeBWCCEBO3//FcQA1f/ADqMQggFjyMnid1f9qzW//p+n/v/m6jjCpclfb7RwEBEqeOqDx+TH2gKCgzatHk",
        "j/a/3jL8w2hLoooooNQG6AZ0LWYdIOs0GqhTVDYWGe+4TpgzWjRnzU2NktlLocjxOyMZJ4qRW4D/8VxADB/8AOgxGTIxsl+f75vff/09f/b/MJduXHfnevf4",
        "yfPxQOCVM/4pJHZ2dnpeO/T7/W8SNdOrV52nBppD56qXVXvdCozXzVqThUR4/h3hc3+C6jBYLGlbQhRQ7Rf/8VxADJ/8AOoxIIRLITRS89NHAQEzZQD/////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////+/O91/8e//2/eozV3e7q6z17ZfjiwIxQbL69VtUvPeaJuhz76Iy7kPCgp55ifN69g83hA4y+Qh2UvzMkmkvaJXnj5hdm0AiiPjlFSIXI2RhPgEdB",
        "ADQHEAAH/zp+AAAAAeAAAICABSEAQ+kZAAAAAQnwAAAAAUGamJAXcRP+EP9WEtXAUCgbvO9fd50CGAX413ERH1hx83X+Ge11AxKgN8H3UDQoL7J/QDf/rl3q",
        "dDKyAbgh3nSAv4TfnN6v+oLwkFD7gKBQX+T2k/9RtPjVqsK1o3o2D/PTD+ArRfOzEvl8/hd38QDTgQgQKgNrg61c8DMFF458D1U6u9a7787Ko/iuUfwOwXLr",
        "f/6z4SJ5RwEANVUA////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////Daf8AqugrSw6O5wNPwr2v354VphEyP4p8fxuBuF4lhy8G3N5f/+Jg3xKDe/5i/Al/528ew5HkOtfhB7jf2EKiAtBwE22+fX4Q4oh1W9T7qbgQ5Pk",
        "iYCL+BEWuoFyK+X4v6hHQQA2BxAACBDOfgAAAAHgAACAgAUhAEUvaQAAAAEJ8AAAAAFBmqigF3ERH4Q/0EKoHMf4MSlnhMy/8GWr/BgolG5AEIBoPohQ+F6T",
        "X8kEalQXWbAi14+h/AOAjwsy+DEpdewYfBYeZBg1P4rXguBMqX9URS7BmpY2k5OGlbuBNVCU0VfBd7rQhi7rgcFo1yergavj65XhERhFYCCECzLybwZKX87c",
        "/kbr+c7Gy4SAjHsPgvJc/1auDSokfkcBADdmAP//////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////yfX+EKT+OrQ2rPC9eg8DZq+ogL5kSC6PniLQgCdeKGKA+Pk0yV8kDwyz9fnYfz8ePh6C",
        "Vhd3ELHECxH8S0ITWL8SWJREEMVUBJdcp7i/WoyAR0EAOAcQAAgiYn4AAAAB4AAAgIAFIQBFdbkAAAABCfAAAAABQZq4sBhy4hq+X/AZMuon8If/CIMMnrf4",
        "Ct5fwP3G1rwEaDdaDrfAT08yHfxPeTyEk+H+Yv+5fwXewYdoBJKZOmC5auaBfDN3yEFvxV+2xwHiE936kT4LTyws3+Msl7Ii+DLX6sYxUsgc3oAg9aFqfqgL",
        "U+eVBCif8WvnYHdnQCDY8KO/57/BBHtK9K/g9v1EUng+4SpIFMJHAQA5dAD/////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////Z38I9wkUAguI/CG/WQe5ZdQ8rl+f",
        "4rkPBH12NhyC1hOPKbmOwvIefvlL//NWh1uu687H1bBzJ8taxItaClor564n6kdBADoHEAAIM/Z+AAAAAeAAAICABSEARbwJAAAAAQnwAAAAAUGayMAYcQ8M",
        "QU/A1Ag8EYQ8EtU6jFFGOYL/rxKUnst/xeTylIf/VMs/O/guV/MENeNqdPY3wqEsILRKXjvfUkFy8c/B6t2T5v/X1hBQvUPHDof6/A2ClRzjFoHM4xXoV/L4",
        "LfAqfg3CHE/E+LfwLqPU2AczCECQ/4NN2Tk/UUXWv9TAR/8Ekh4I6EfwYIPcAn56N/PGPR3uRwEAO3gA////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9u",
        "onoTDM0uegE/GrnEl//QeMhFKEFmTtNZzRzQ+IgixCD7x7D0kSq1+XgriB79v3495UVZtNubTbFrYzvCPxVHQQE0AUAAAAHAAyuAgAUhAEPR2f/xXEANH/wA",
        "6jElhONC+Nf65u/X/93j/9P1FuPFzW7M1U9/MFQz1tTt/CKurrfuvnN3+zv9H30ZPPPOqcGnUfUdQC1KUK8PUdE9UfTPUpeWTWs+oamHdEl9LtrTlhiGU4kh",
        "l7dgddC///FcQAyf/ADsMSWE0Ur+tf/Dbx/9Pn/937wdbqXkiu/OX46gmmep9T+6e50q6vDXw5bz/5dX9q0LRpT+9PfpQkcBARVGPJjyUhhicSO5JciYnqkV",
        "1QGyU81FU4Ih6ctGI/JC5R3qYa//8VxADL/8AOwxIIhZGShY61x/fe+ef/rn/l/1l5JLmKvOv0+JXr42HAWgyv8/2AyAMDNeOg/4OfsMhDD1/VfThPQppR/A",
        "9HUOrJ+C5kaNGgf1+L5C7nviHK1qN/IMp/RIjIikcP/xXEAM3/wA6DEgiFkZOFDXWv7eN1z/4/j/z/62kReJbnx9818+wHWQ5nXbjw5ZRwEBFmXoes5/O/qT",
        "y0BkRdxRFFcUQcGXGL0ImRAkD9ydimXSMV6yE5aM/FzTm0TmnvGI+RhTkvazvfj/8VxAC//8AOgxGRZCSLVr/jN3P/7X2/9f9LivPNzKnEr59qnjzgIQLKvL",
        "gAoKDRU2nCVevQBf8i8AJdFFHRQaha6DChqh1HhYiv7OFrKxle2wR1sMRawb7BILCiIi4P/xXEAMn/wA6DEZMkI5ucTj/pOb8f/H7f/f/HEy4mXUtXtHAQEX",
        "/fd5mhDoxbe34AgMDPi+M/2L6/f5PBIyxPvkVQiiygkLsKSE2Aw83TGnsSFXR4bqE0asYcjc7XH4V0SArfRX3VuA//FcQAz//ADoMSE2Mnidfnj/tVbz/9vH",
        "/z/N1LJfPCL/j21PfzgGs5qWSj+VTlLEESKWpDKP3BF1AeKAk87b2tj3f5sS2wa/M4DXlYzF6rvziUIMjPqMJzj7ya2co+OCYkSVFkShwP/xXEAMX/wA7jEY",
        "koGzjkcBAThkAP//////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////7P055m//6vX/v/ui2a1zdQ8fGT59rBHD4fW3mq6ur3avbN35vv7nZPfv37998VCl74vdgywvc54nzT35F4r86DY+sYc0NH1",
        "aF1s4ocyJRK82yfAR0EAPAcQAAhFin4AAAAB4AAAgIAFIQBHAlkAAAABCfAAAAABQZrY0BhxHBh/5uT6S/1QC8HAFFTsvYEcOK3iAIYbrWFTYG/g8bHECx//",
        "Lusb3UomHoGy3BJz1QMzqf1TrjDq7nAJHPo0BXwhbn4sLL7L/waQsvfqZPAncYq8v0qIZ18HXP8/xX2EAMmIQLetAuTLUepVHwkeAEiBi5fw3o/L43/frFXB",
        "lxXOT6/9Wyf3/nufEu8/xI/nEB5HAQA9awD/////////////////////////////////////////////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////LDnH8CUglE/g9U3NAhTnf9SoAUr8BocR4iH3neW2D++s7yC3vi93zy4twHwbpjx",
        "vnHV+Dp04QWJJESaf8IIZUxkxnMZMZ/qAEAIuEdBAD4HEAAIVx5+AAAAAeAAAICABSEAR0ipAAAAAQnwAAAAAUGa6OAZc7+D5UAXcDEo2m34H9RZ91BGK5PZ",
        "L/1c589A3f4pfOCfP68RS7r7fgR/oGSxzvUieAuuX8GwMfV/g/VqJ9l+YPeTziv/VAPoIAYeuy/8FkHy/yfZi/+IW+AkKEIFviwMCBYVFWoNj//wcf/B0pEF",
        "13iwW6otS5jxjfjBoMj43lTl4m4Gjf6haoLF6vPQF/AlFJzzRwEAP3AA////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////79XoetdJLMaMaN65AJZ3lwYAbsQg+8Qn4MQf",
        "SzfsNoPPtcEuY74iHYjF1yOJOd8/n87zcCRPFQGeg18+BBUqKksGIFPiPuBHQQAwBxAACGiyfgAAAAHgAACAgAUhAEeO+QAAAAEJ8AAAAAFBmvjwGXO94MFo",
        "vwgsElHG3nr9YHAIg7r3gr84Efzf54CP4Mtr/zyqGbvzx///+wivjH9eN8e+CzCCwFkGn/XD8GHigiqdc9UECvC6to/goWDuAkVyZYvzwTv9QbWMQJv+bXuf",
        "k4CQoQgX9wFEcF0QlX8SaxroQwa7USONUmLflgsVeR1IgOMfghuf5uJvx6xSAa3p0/vrjkcBADFcAP//////////////////////////////////////////",
        "//////////////////////////////////////////////////////////////////////////////9UBbH8yCUn34px+bADteDoJji1vi1v8CAp2x+4TqcU",
        "/kShDrwCX8mDD8BBWIQf8GOf0HioLPJ8h4f8GOe9DsgNJ+J7PH+DHJH6D3V60ZW+Q75/4DBxEP5/O8/3R0EAMgcQAAh6Rn4AAAAB4AAAgIAFIQBH1UkAAAAB",
        "CfAAAAABQZsADLm9dB79C1lk9P3/4J1rn+KgIbjPqBZl9f/r/9UU/qZFX1d/8E6xSxAufENyw5zDLtX/F54DvIY7/P/49ZepKgMDrrgYFznwQKcgMOS1HxwB",
        "6YF9W6TX51xdZ6/w3Wb1pUq/QLl8XFfX19fwY8nP8gmCHr+BAxC9QFFz8/oOFQWbIeH+u6++eP0HjMJdEPDfXZ377ERHAQAzowD/////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "///////////////////////////////////////////////////////////////////////////yF//kP9fWqVRC9Qig1/vmEIN19UdBATkBQAAAAcADLICA",
        "BSEARdcT//FcQAw//ADuMRkyMkC5xfH96vPf/+1n/6fyIiZcuZ8/Gs9dQAjRtnl/YCMjus33+91f3rd+nYWS8889peAeY9yeexayp1nXPb4McKkoQF5ywwZV",
        "NkqyZ/7BnCxCSJGFeP/xXEAMv/wA7jEgiFkZJFrrzf/Sc98//xb/+3+1SJSJUk+frNe/mgsRko03h+ReDBgzXjkfbb+s5hYfr9T19AUv9K6I11q6RwEBGrRd",
        "oMilt9/cvFkSE4xhVRojfRHW30G03mYRpNbBXv/xXEANf/wA6jEIUHsZKNifD+1c6z/+z4/9/30OKrrtWr33xc3YOE90qzXmOYZhkT5nZl5jqYCChgnCwMiL",
        "lEjviuRpiiYiSIgWmaC878lPRvdOExtUhA5K+zO5n0MuifZ4UxLlMyui6+N+//FcQAxf/ADuMRkuMbOr1/Xncr/+L+3/4/8yLupeSKrx5u/t5AISSbLZ0QQF",
        "BSVHAQEb2aY/I7V/ZJBs2bGzZHZ7LcNDb7JI4eNrcmF/XvNvLKDAjGrvs34tn4aEJWFjYsJF1p7+//FcQAw//ADqMSWksVNOv7Yrx/4/r/5/86q3TBab9/qV",
        "69oKvHO9bpfBJiYnHSx40/4L4d8TBIKKIoiqRDip/FESCLBBRE/7tNUPbNKFBOHgiGPD1xjRjFTUY0bO+RG9+P/xXEAMv/wA7jEZMjJope2tf61zzz/6e//r",
        "/ta10qa5uuPt7UcBARwn2+KBlE3dv+/cAo7OztW+W/nFfJJIR50UUfSBb0FDw1rCwajo3HWGPX2bFGXXPKIoQ5E65Z4oRhaYsZmMCami3P/xXEAL//wA6DEZ",
        "LjJItTqf2yud//t9v/t/vcVc358VrWX7+2PHtAxoeH13eAGRkxNXrfO+Hf08Qz86p9kM50bHz2vn2TL3oKeVt0m9TXALwn1Cd0xfeKm8wLyMN0Lc//FcQA2f",
        "/ADuMSCSknKd18c/3revX/9pRwEBPWMA////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////7vpltY1RJfMjICjQE29G4u11dXu5+7vXe/qm79g511YeeeY88lLyUhKUyMYrSmTvS8MRvSskPMkq",
        "6I9OVyi0BSiJtqUkRAhZPzXRoSsFKVYRI4BHQQA0BxAACIvafgAAAAHgAACAgAUhAEkbmQAAAAEJ8AAAAAFBmxAMuXEVQR6GrJ7Nr6Ah8+eA0AXBty/BiUvz",
        "hLxPEDV/qbVIs/UkESm48CGeKph/wsy9cH/wRgkrVQzHY/mQil+JOy+p7n5Pq0A0PCw6ggSc1R3b/vAIiDHUN+AHuqJS8G/JAaPPxK/vz9N9Xf9WTy+fzvII",
        "gjyfyYLvpGbHww4ygjJX4vx/VeK+q7EQzyeEEHqdNt/xC0cBADWUAP//////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "/////////8nEVqJaCpsh4f8GO8GGIX6D2eQ8PyScTLySAw8nyfJxJ7qAR0EANgcQAAidbn4AAAAB4AAAgIAFIQBJYekAAAABCfAAAAABQZsgDLnn+YI+IBB/",
        "rC2efV5KQGlR/9gv9Ah+C/J7vAR0GHq5j9SEE1+C+R3wGcI3cAlq0y+fAIoSeWK/Ea0qz+I4murgu/XBcIcHeHcift3oILFsUL0wCU6bXa/zgxXuWAQFRLSI",
        "PBHJFwDm49hp0/yeb96oC0ErPh0IFn/A8RJbm+oFvrV+bv6/84oS0IBKvxHSavUqCzZHAQA3ewD/////////////////////////////////////////////",
        "/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////1mz",
        "zdjtytuQs3JM3NfXzdnYI64Lq84IhLQgSr8mk3NqZANKLf3HRh5UAjwrl8K5c683ETcs/z/EfPxH3EdBADgHEAAIrwJ+AAAAAeAAAICABSEASag5AAAAAQnw",
        "AAAAAUGbMAy4icI/BB6/CNe+Hf179QqbAhf/6n69fWuBt/g7zvxn8PY/UGtBxde9Q89zf1rriH+pEB3b4NVtk8w//8nnIRcGHqYWECYjsTMa4ne9eLv+Kr1A",
        "RfDy5DzxmK6Gzy/wc/3AQqlTHvQG/gLM7ZiDwQ9dcGgIQ9WoDolJXrQKvw+qY7VQU3wNB/fyULTJE+Ih+SuX0HioRwEAOZcA////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////LPV6vJEfEfEdnYflFsPRHYS7NEfFa2zvEn5YnxCD8ZBHQQE+AUAAAAHAA2iAgAUh",
        "AEfcTf/xXEAM//wA7DEhNjJope18f9MZ6/8fn/9/xCXRWqur9/J66sHUFR9Dy+wWpaloJoDkBvDKJtSmaxDR6z+vVPP1Tz1/o5qJwoNBoyz9M56dlF739Nrj",
        "Y0aDEjNmXo4DEdiJVPfZGfD/8VxADF/8AOwxETIyYKmqnzvffP/9uv/v/ta84rPPi7qT7fF57+2DDS/ufyeQGLF6za/2qvk0Bnv25dE5dyT+3EcBAR+SJjkn",
        "aGIQ8gzj2PkzLQZ1heUvy1OteHD5SKgkFZIyCRz/8VxADJ/8AOoxJYTRS446/7Vzef/xfn/z/31JKS81V5nr71Pn2DPGIdT5v9MRMTGehp90j558dewyEOjp",
        "o6aKKI6AowWbgb9BKq3V1BXCMbhQTtfbfttjHQzONHyFDcChMvXg//FcQAyf/ADuMSCEOyk40OuuP+1bvP/r+f/v/vlXqZJzqtSudRvWBbgAtLbuPOQiJcve",
        "RwEBEBWLyVu8P8VxYN1RRRBCFIiiREEIQCYWIJAHJBE1FPOvFfaRrAvbTDT5Vx34IMAzgi7/8VxADB/8AO4xGS4yYKk+Nf3zG//r+3/v/3uq87JcKnv9Y9e1",
        "CHYKP9x+wCjo7YY9z/1/QewkJf0oWsy4DUUOmXANw6R1JM+tNvMyMpnSF0474yRZM0QFDurdHKXknfj/8VxAD//83gIATGF2YzU5LjM3LjEwMAABxGJCbGTF",
        "U5+9/8VzfP9HAQER+3v/8/zovWVx3xhr1xFTAsoZ+vKI7JagiCJGkzpg3V2uh4GdAGxPDPE+IlKhmLKd9IJqT0aD9aLIQJEXdkgdcKKoJqyshsRaYvGBSfXK",
        "N5oilElE0CpJ4P/xXEAL//wBKlELwkS++ab9/4+f9vj7zpw0u5JLS0D5/Mx8PttTIln2G0J+fzB/t9gn5/MH+32Cfn8zH+32Cfn8wf7bQn57xh9rgn5xgfba",
        "B1xbf6QaUaWhNKIgZ+UX/0cBATInAP//////////////////////////////////////////////////8VxAEj/8ARSTsspzZLmyXNkuX/9P/7/HWr1fj//P",
        "/7/XXF3x8//1v+fM1xL4//vfjjriTQc3Irt5+at+55N5Mrukjl0GCSoME3QYJCboMDBISE3QYGCSuK52BMVCgfH+cjERiioKKiLjRF8qC+UVFBD5fKiiKLHk",
        "ImBbdRy3/bsruqybEI3cvoJvPkghzOzcR0EBM51A////////////////////////////////////////////////////////////////////////////////",
        "////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////",
        "////////AAABwAAUgIAFIQBJ4Yf/8VxAAZ/8ARiBtHA=",
    ]
}

#else
import Foundation

/// Release builds: demo mode does not exist.
enum MedxDemoMode {
    static let isOn = false
    static func install() {}
}
#endif
