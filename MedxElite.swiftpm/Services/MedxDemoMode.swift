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
            explanation: "<p><b>Toxic shock syndrome toxin-1 (TSST-1)</b> of <i>Staphylococcus aureus</i> is a superantigen. It cross-links MHC class II with the T-cell receptor outside the peptide groove, causing massive cytokine release. Menstrual TSS is classically linked to tampon use.</p>"
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
            (id: "test_4", name: "Clinical Practice Paper", subject: "Medicine · Surgery · OBG · Pediatrics", questions: 100, gradable: false)
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
            MedxDemoQuestions.question(pool[(seed + index * 7) % pool.count], id: base + index + 1, number: index + 1, reference: nil)
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

#else
import Foundation

/// Release builds: demo mode does not exist.
enum MedxDemoMode {
    static let isOn = false
    static func install() {}
}
#endif
