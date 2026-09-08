//
//  MedicationDatabase.swift
//  Stanford Preoperative Medication
//
//  Source: PARC Pre-Operative Medication Guidelines, Stanford Children's Health,
//  Pediatric Anesthesia & Pain Medicine. Updated 5/21/2026.
//  Authors: Genevieve D'Souza MD FASA; Erin Herse CPNP-AC; Melissa Martz CPNP-AC
//
//  NOTE: These are PEDIATRIC guidelines. See GuidelineMeta.scope.
//

import Foundation

// MARK: - Guideline metadata

enum GuidelineMeta {
    static let title = "PARC Pre-Operative Medication Guidelines"
    static let revision = "5/21/2026"
    static let source = "Stanford Children's Health, Pediatric Anesthesia & Pain Medicine"
    static let scope = "Pediatric. Adult perioperative protocols may differ."
    static let defaultRule =
        "Unless specifically stated, patients should continue their daily medications "
        + "with a sip of water even when NPO for surgery."
}

// MARK: - Severity

/// Drives UI color only. Never drives clinical logic.
enum Severity: String, Codable, Hashable {
    case takeAsDirected
    case hold
    case consult
    case conditional
}

// MARK: - Action

/// One concrete instruction. Replaces the old hold/caution/continue enum.
enum Action: Codable, Hashable {
    case takeAsDirected
    case holdDayOfSurgery
    case holdHours(Int)
    case holdDays(Int)
    case consult(String)          // who to consult
    case variable(String)         // genuinely case-by-case

    var severity: Severity {
        switch self {
        case .takeAsDirected:                      return .takeAsDirected
        case .holdDayOfSurgery, .holdHours, .holdDays: return .hold
        case .consult:                             return .consult
        case .variable:                            return .conditional
        }
    }

    var label: String {
        switch self {
        case .takeAsDirected:      return "Take as directed"
        case .holdDayOfSurgery:    return "Hold day of surgery"
        case .holdHours(let h):    return "Hold \(h) hours prior to surgery"
        case .holdDays(let d):
            return d == 21 ? "Hold 3 weeks prior to surgery" : "Hold \(d) days prior to surgery"
        case .consult(let who):    return "Consult \(who)"
        case .variable(let what):  return what
        }
    }

    /// Hours before scheduled surgery time that the last dose may be taken.
    /// nil means no fixed offset (take as directed, consult, or variable).
    var holdWindowHours: Int? {
        switch self {
        case .holdHours(let h):  return h
        case .holdDays(let d):   return d * 24
        case .holdDayOfSurgery:  return nil   // calendar-day rule, not an hour offset
        default:                 return nil
        }
    }
}

// MARK: - Conditional

/// A branch that depends on indication, dose, route, or dosing frequency.
/// The whole point of this type is that the app must ASK rather than guess.
struct Conditional: Codable, Hashable, Identifiable {
    let id: String
    let question: String     // shown to the clinician
    let whenLabel: String    // the branch
    let action: Action
    var detail: String?

    init(_ question: String, _ whenLabel: String, _ action: Action, _ detail: String? = nil) {
        self.id = "\(question)|\(whenLabel)"
        self.question = question
        self.whenLabel = whenLabel
        self.action = action
        self.detail = detail
    }
}

// MARK: - Guidance

struct Guidance: Codable, Hashable {
    let action: Action
    var detail: String?
    var conditionals: [Conditional] = []
    var pediatricCardiac: String?
    var concern: String?

    /// True when the app cannot resolve an answer without more input.
    var requiresInput: Bool { !conditionals.isEmpty }

    var severity: Severity { requiresInput ? .conditional : action.severity }
}

// MARK: - Drug

enum PARCCategory: String, Codable, CaseIterable {
    case cardiovascular   = "Cardiovascular"
    case endocrine        = "Endocrinology"
    case gastrointestinal = "GI"
    case hematology       = "Hematology"
    case neuroBehavioral  = "Neurology & Behavioral"
    case pain             = "Pain"
    case nsaid            = "NSAIDs"
    case respiratory      = "Respiratory"
    case rheumImmune      = "Rheumatology & Immune"
    case recreational     = "Recreational Substances"
    case supplement       = "Vitamins, Supplements & Herbals"
    case device           = "Devices"
}

struct Drug: Identifiable, Codable, Hashable {
    let id: String              // canonical slug. THE dedup key.
    let generic: String
    let brands: [String]
    let drugClass: String
    let category: PARCCategory
    let guidance: Guidance
    var halfLifeHours: Double?

    /// Every string that should resolve to this drug.
    var searchNames: [String] { [generic] + brands }

    var displayName: String {
        brands.isEmpty ? generic : "\(generic) (\(brands.joined(separator: ", ")))"
    }
}

// MARK: - Cross-drug rules

/// Rules that depend on the whole med list, not on one drug.
/// These run AFTER matching, over the resolved set.
struct InteractionRule: Identifiable {
    let id: String
    let triggerID: String            // drug that gets modified
    let requiresAnyOf: Set<String>   // drug ids that activate the rule
    let revisedAction: Action
    let message: String
}

// MARK: - Build helpers

private func slug(_ s: String) -> String {
    s.lowercased()
        .replacingOccurrences(of: "/", with: "-")
        .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
        .joined()
}

private typealias Entry = (generic: String, brands: [String])

private func build(
    _ entries: [Entry],
    _ drugClass: String,
    _ category: PARCCategory,
    _ guidance: Guidance,
    halfLives: [String: Double] = [:]
) -> [Drug] {
    entries.map { e in
        Drug(
            id: slug(e.generic),
            generic: e.generic,
            brands: e.brands,
            drugClass: drugClass,
            category: category,
            guidance: guidance,
            halfLifeHours: halfLives[e.generic]
        )
    }
}

// MARK: - Database

enum MedicationDatabase {

    // ---------------------------------------------------------------- CARDIO

    private static let cardiovascular: [Drug] =
        build([("midodrine", ["Orvaten"])],
              "Alpha-1 adrenergic agonists", .cardiovascular,
              Guidance(action: .takeAsDirected, concern: "Hypotension"))

        + build([("clonidine", ["Catapres"]), ("prazosin", ["Minipress"])],
              "Alpha-1 antagonist / Alpha-2 agonists", .cardiovascular,
              Guidance(action: .takeAsDirected, concern: "Rebound hypertension"))

        + build([("captopril", ["Capoten"]), ("enalapril", ["Vasotec"]),
                 ("lisinopril", ["Prinivil", "Zestril"])],
              "ACE inhibitors", .cardiovascular,
              Guidance(action: .holdDayOfSurgery,
                       detail: "Do not give after 7pm the night before day of surgery.",
                       concern: "Intraoperative hypotension"))

        + build([("candesartan", ["Atacand"]), ("irbesartan", ["Avapro"]),
                 ("losartan", ["Cozaar"]), ("olmesartan", ["Benicar"])],
              "Angiotensin receptor blockers (ARB)", .cardiovascular,
              Guidance(action: .holdDayOfSurgery,
                       detail: "Do not give after 7pm the night before day of surgery.",
                       concern: "Intraoperative hypotension"))

        + build([("atenolol", ["Tenormin"]), ("carvedilol", ["Coreg"]),
                 ("labetalol", ["Normodyne"]), ("metoprolol", ["Lopressor", "Toprol XL"]),
                 ("nadolol", ["Corgard"]), ("propranolol", ["Inderal"])],
              "Beta blockers", .cardiovascular,
              Guidance(action: .takeAsDirected, concern: "Risk of MI"))

        + build([("amlodipine", ["Norvasc"]), ("diltiazem", ["Cardizem"]),
                 ("isradipine", ["DynaCirc"]), ("verapamil", ["Calan"])],
              "Calcium channel blockers", .cardiovascular,
              Guidance(action: .takeAsDirected, concern: "Hypertension"))

        + build([("acetazolamide", ["Diamox"]), ("bumetanide", ["Bumex"]),
                 ("chlorothiazide", ["Diuril"]), ("eplerenone", ["Inspra"]),
                 ("furosemide", ["Lasix"]), ("hydrochlorothiazide", ["Microzide"]),
                 ("spironolactone", ["Aldactone"])],
              "Diuretics (loop, potassium sparing, thiazide)", .cardiovascular,
              Guidance(
                  action: .variable("Depends on indication"),
                  conditionals: [
                      Conditional("What is this diuretic prescribed for?",
                                  "Hypertension", .holdDayOfSurgery),
                      Conditional("What is this diuretic prescribed for?",
                                  "Fluid overload / heart failure", .takeAsDirected)
                  ],
                  pediatricCardiac: "Variable. Discuss with team.",
                  concern: "Can cause hypovolemia and hypotension"))

        + build([("potassium supplement", ["potassium chloride", "K-Dur", "Klor-Con"])],
              "Electrolytes", .cardiovascular,
              Guidance(action: .takeAsDirected,
                       detail: "Hold if also holding a potassium-wasting diuretic.",
                       concern: "Hyperkalemia"))

        + build([("coenzyme Q10", ["CoQ10", "ubiquinone"]), ("fish oil", ["omega-3"])],
              "Nutraceuticals", .cardiovascular,
              Guidance(action: .holdDays(7),
                       detail: "Consider holding for 7 days prior to surgery.",
                       concern: "Bleeding"))

        + build([("sildenafil", ["Viagra", "Revatio"]), ("tadalafil", ["Cialis"])],
              "PDE5 inhibitors", .cardiovascular,
              Guidance(action: .takeAsDirected, concern: "Pulmonary hypertensive crisis"))

    // ------------------------------------------------------------- ENDOCRINE

    private static let endocrine: [Drug] =
        build([("desmopressin", ["DDAVP"])],
              "Anti-diuretic agents", .endocrine,
              Guidance(action: .takeAsDirected, concern: "Electrolyte abnormalities"))

        + build([("methimazole", ["Tapazole"])],
              "Anti-thyroid agents", .endocrine,
              Guidance(action: .takeAsDirected, concern: "Hyperthyroidism"))

        + build([("phentermine", []), ("phentermine/topiramate", ["Qsymia"])],
              "Appetite suppressants", .endocrine,
              Guidance(action: .holdDays(7),
                       detail: "Hold phentermine for 7 days prior to surgery. "
                             + "If topiramate dose is greater than 46mg, Bariatric Surgery team "
                             + "to taper off or order topiramate only. "
                             + "Do not discontinue topiramate suddenly.",
                       concern: "Hemodynamic instability; seizure withdrawal"))

        + build([("deflazacort", ["Emflaza"]), ("hydrocortisone", []),
                 ("methylprednisolone", ["Medrol"]), ("prednisone", []),
                 ("prednisolone", ["Orapred"]), ("vamorolone", ["Agamree"])],
              "Corticosteroids", .endocrine,
              Guidance(action: .takeAsDirected,
                       detail: "Stress dosing recommendations from Endocrinology or prescribing service.",
                       concern: "Adrenal insufficiency / hypotension"))

        + build([("dulaglutide", ["Trulicity"]), ("liraglutide", ["Saxenda", "Victoza"]),
                 ("semaglutide", ["Ozempic", "Wegovy", "Rybelsus"]),
                 ("tirzepatide", ["Mounjaro", "Zepbound"])],
              "GLP-1 agonists", .endocrine,
              Guidance(
                  action: .variable("Depends on dosing frequency"),
                  detail: "Patients on weekly injections for diabetes management will need a bridge through Endocrinology.",
                  conditionals: [
                      Conditional("How often is this injected?", "Weekly", .holdDays(7)),
                      Conditional("How often is this injected?", "Daily", .holdHours(24))
                  ],
                  pediatricCardiac: "For Stanford-referred ACHD patients, hold on day of surgery "
                                  + "regardless of dosing frequency. Consider a clear liquid diet for 24 hours.",
                  concern: "Hypoglycemia; delayed gastric emptying"))

        + build([("teduglutide", ["Gattex"])],
              "GLP-2 analogs", .endocrine,
              Guidance(action: .holdHours(48), concern: "Delayed gastric emptying"))

        + build([("insulin pump", ["Medtronic", "Omnipod", "Tandem"]),
                 ("continuous glucose monitor", ["CGM", "Dexcom", "Libre"])],
              "Insulin pumps and CGMs", .device,
              Guidance(action: .consult("Endocrinology"),
                       detail: "Consult Endocrinology for day-of-surgery recommendations and refer to pathway.",
                       concern: "Hypoglycemia"))

        + build([("insulin aspart", ["Novolog", "Fiasp"]), ("insulin glulisine", ["Apidra"]),
                 ("insulin lispro", ["Humalog", "Admelog"])],
              "Insulin, rapid-acting", .endocrine,
              Guidance(action: .consult("Endocrinology"),
                       detail: "Consult Endocrinology for day-of-surgery recommendations.",
                       concern: "Hypoglycemia"))

        + build([("NPH insulin", ["Humulin N", "Novolin N"])],
              "Insulin, intermediate-acting", .endocrine,
              Guidance(action: .consult("Endocrinology"),
                       detail: "Consult Endocrinology for day-of-surgery recommendations.",
                       concern: "Hypoglycemia"))

        + build([("insulin detemir", ["Levemir"]), ("insulin glargine", ["Lantus", "Basaglar", "Toujeo"])],
              "Insulin, long-acting", .endocrine,
              Guidance(action: .consult("Endocrinology"),
                       detail: "Consult Endocrinology for day-of-surgery recommendations.",
                       concern: "Hypoglycemia"))

        + build([("metformin", ["Glucophage"])],
              "Oral hypoglycemic agents", .endocrine,
              Guidance(action: .holdHours(24), concern: "Hypoglycemia; lactic acidosis"))

        + build([("dapagliflozin", ["Farxiga"]), ("empagliflozin", ["Jardiance"])],
              "SGLT2 inhibitors", .endocrine,
              Guidance(action: .holdHours(72),
                       detail: "If not held appropriately, check bicarbonate and glucose 2-4 hours post-op.",
                       pediatricCardiac: "If not held appropriately, elective procedures will be cancelled.",
                       concern: "Hypoglycemia; risk for euglycemic DKA"))

    // -------------------------------------------------------------------- GI

    private static let gastrointestinal: [Drug] =
        build([("aprepitant", ["Emend"]), ("granisetron", ["Kytril"]),
               ("ondansetron", ["Zofran"]), ("scopolamine", ["Transderm Scop"])],
              "Antiemetics", .gastrointestinal,
              Guidance(action: .takeAsDirected, concern: "Nausea"))

        + build([("esomeprazole", ["Nexium"]), ("famotidine", ["Pepcid"]),
                 ("lansoprazole", ["Prevacid"]), ("omeprazole", ["Prilosec"]),
                 ("pantoprazole", ["Protonix"])],
              "H2-blockers and PPIs", .gastrointestinal,
              Guidance(action: .takeAsDirected, concern: "Reflux"))

        + build([("bisacodyl", ["Dulcolax"]), ("docusate sodium", ["Colace"]),
                 ("lactulose", ["Duphalac"]), ("polyethylene glycol", ["Miralax"]),
                 ("senna", ["Senokot"])],
              "Laxatives", .gastrointestinal,
              Guidance(action: .holdDayOfSurgery,
                       conditionals: [
                           Conditional("Is this for a GI cleanout?", "No, routine use", .holdDayOfSurgery),
                           Conditional("Is this for a GI cleanout?", "Yes, GI cleanout", .holdHours(6))
                       ],
                       concern: "Aspiration"))

        + build([("erythromycin", ["E.E.S"]), ("linaclotide", ["Linzess"]),
                 ("metoclopramide", ["Reglan"]), ("prucalopride", ["Motegrity"])],
              "Motility agents", .gastrointestinal,
              Guidance(action: .takeAsDirected, concern: "Delayed gastric emptying"))

    // ------------------------------------------------------------ HEMATOLOGY

    private static let hematology: [Drug] =
        build([("heparin", [])],
              "Anticoagulants", .hematology,
              Guidance(action: .holdHours(4),
                       detail: "Hold at least 4 hours prior to surgery.",
                       concern: "Bleeding"))

        + build([("warfarin", ["Coumadin"])],
              "Anticoagulants", .hematology,
              Guidance(action: .consult("prescriber"),
                       detail: "May require bridging therapy.",
                       concern: "Bleeding"))

        + build([("aspirin", ["ASA", "Ecotrin"])],
              "Antiplatelets", .hematology,
              Guidance(action: .consult("proceduralist and prescriber"), concern: "Bleeding"))

        + build([("clopidogrel", ["Plavix"])],
              "Antiplatelets", .hematology,
              Guidance(action: .holdDays(5),
                       detail: "Consult proceduralist and prescriber. Consider holding for 5 days.",
                       concern: "Bleeding"))

        + build([("dipyridamole", ["Persantine"])],
              "Antiplatelets", .hematology,
              Guidance(action: .holdDays(2),
                       detail: "Consult proceduralist and prescriber. Consider holding for 2 days.",
                       concern: "Bleeding"))

        + build([("prasugrel", ["Effient"]), ("ticlopidine", ["Ticlid"])],
              "Antiplatelets", .hematology,
              Guidance(action: .holdDays(7),
                       detail: "Consult proceduralist and prescriber. Consider holding for 7 days.",
                       concern: "Bleeding"))

        + build([("dabigatran", ["Pradaxa"])],
              "Direct thrombin inhibitors", .hematology,
              Guidance(action: .consult("prescriber"),
                       detail: "No lumbar puncture within 7 days of last dose.",
                       concern: "Bleeding"))

        + build([("apixaban", ["Eliquis"]), ("fondaparinux", ["Arixtra"]),
                 ("rivaroxaban", ["Xarelto"])],
              "Factor Xa inhibitors", .hematology,
              Guidance(action: .consult("prescriber"),
                       detail: "Consider holding for 48 hours.",
                       concern: "Bleeding"))

        + build([("dalteparin", ["Fragmin"]), ("enoxaparin", ["Lovenox"])],
              "Low molecular weight heparin", .hematology,
              Guidance(
                  action: .variable("Depends on indication"),
                  conditionals: [
                      Conditional("What is the indication?", "Anticoagulation dose", .holdHours(24)),
                      Conditional("What is the indication?", "DVT prophylaxis", .holdHours(12))
                  ],
                  pediatricCardiac: "Guidance dependent on specific procedure and patient factors.",
                  concern: "Bleeding"))

    // ------------------------------------------------- NEUROLOGY & BEHAVIORAL

    private static let neuroBehavioral: [Drug] =
        build([("pyridostigmine", ["Mestinon"])],
              "Acetylcholinesterase inhibitors", .neuroBehavioral,
              Guidance(action: .takeAsDirected,
                       detail: "Restart ASAP when hemodynamically stable post-op. "
                             + "Consult Neurology if oral doses will not be feasible post-op. "
                             + "Parenteral substitutions: IM is 1/10th the usual oral dose; "
                             + "IV is 1/30th the usual oral dose.",
                       concern: "Muscarinic side effects"))

        + build([("hydroxyzine", ["Atarax", "Vistaril"])],
              "Antihistamines", .neuroBehavioral,
              Guidance(action: .takeAsDirected))

        + build([("atomoxetine", ["Strattera"]), ("guanfacine", ["Tenex", "Intuniv"]),
                 ("viloxazine", ["Qelbree"])],
              "ADHD non-stimulants", .neuroBehavioral,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("amphetamine/dextroamphetamine", ["Adderall"]),
                 ("methylphenidate", ["Concerta", "Ritalin"]),
                 ("dexmethylphenidate", ["Focalin"]),
                 ("lisdexamfetamine", ["Vyvanse"])],
              "ADHD stimulants", .neuroBehavioral,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("N-acetylcysteine", ["NAC", "Mucomyst"])],
              "Antioxidants", .neuroBehavioral,
              Guidance(action: .holdDays(7), concern: "Bleeding; drug interactions"))

        + build([("isocarboxazid", ["Marplan"]), ("phenelzine", ["Nardil"]),
                 ("tranylcypromine", ["Parnate"]), ("linezolid", ["Zyvox"]),
                 ("rasagiline", ["Azilect"]), ("selegiline", ["Eldepryl", "Emsam"])],
              "Antidepressants: MAOIs", .neuroBehavioral,
              Guidance(action: .takeAsDirected,
                       detail: "Anesthesiologist must be informed of the need to use MAOI-safe anesthesia. "
                             + "Avoid ephedrine, meperidine, and dextromethorphan. Phenylephrine is acceptable. "
                             + "Consult Neurology ASAP post-op if unable to take doses.",
                       concern: "Severe hypertension and serotonin syndrome from interaction with anesthesia medications"))

        + build([("citalopram", ["Celexa"]), ("desvenlafaxine", ["Pristiq"]),
                 ("duloxetine", ["Cymbalta"]), ("escitalopram", ["Lexapro"]),
                 ("fluoxetine", ["Prozac"]), ("paroxetine", ["Paxil"]),
                 ("sertraline", ["Zoloft"])],
              "Antidepressants: SSRIs and SNRIs", .neuroBehavioral,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("amitriptyline", ["Elavil"]), ("bupropion", ["Wellbutrin"]),
                 ("desipramine", ["Norpramin"]), ("doxepin", ["Silenor"]),
                 ("imipramine", ["Tofranil"]), ("mirtazapine", ["Remeron"]),
                 ("nefazodone", ["Serzone"]), ("nortriptyline", ["Pamelor"]),
                 ("trazodone", ["Desyrel"])],
              "Antidepressants: other", .neuroBehavioral,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("aripiprazole", ["Abilify"]), ("olanzapine", ["Zyprexa"]),
                 ("quetiapine", ["Seroquel"]), ("risperidone", ["Risperdal"])],
              "Antipsychotics", .neuroBehavioral,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("carbamazepine", ["Tegretol"]), ("clonazepam", ["Klonopin"]),
                 ("felbamate", ["Felbatol"]), ("gabapentin", ["Neurontin"]),
                 ("lamotrigine", ["Lamictal"]), ("levetiracetam", ["Keppra"]),
                 ("oxcarbazepine", ["Trileptal"]), ("phenytoin", ["Dilantin"]),
                 ("pregabalin", ["Lyrica"]), ("primidone", ["Mysoline"]),
                 ("topiramate", ["Topamax"]), ("valproic acid", ["Depakote"]),
                 ("zonisamide", ["Zonegran"])],
              "Anti-seizure medications", .neuroBehavioral,
              Guidance(action: .takeAsDirected,
                       detail: "Take as directed unless instructed to hold by surgeon or Neurology.",
                       concern: "Breakthrough seizures"))

        + build([("alprazolam", ["Xanax"]), ("diazepam", ["Valium"])],
              "Benzodiazepines", .neuroBehavioral,
              Guidance(action: .takeAsDirected,
                       concern: "Withdrawal: agitation, delirium, hypertension, seizures"))

        + build([("cannabidiol", ["Epidiolex"])],
              "Cannabinoids", .neuroBehavioral,
              Guidance(action: .takeAsDirected))

        + build([("lithium", ["Eskalith", "Lithonate"])],
              "Mood stabilizers", .neuroBehavioral,
              Guidance(action: .takeAsDirected,
                       detail: "Needs a CMP within 30 days of day of surgery.",
                       concern: "Electrolyte abnormalities"))

        + build([("doxylamine", ["Unisom"]), ("melatonin", [])],
              "Sleep-promoting agents", .neuroBehavioral,
              Guidance(action: .takeAsDirected))

    // ------------------------------------------------------------------ PAIN

    private static let pain: [Drug] =
        build([("buprenorphine", ["Suboxone", "Subutex"])],
              "Partial mu-opioid receptor agonists", .pain,
              Guidance(action: .takeAsDirected, concern: "Withdrawal; increased pain"))

        + build([("codeine", []), ("fentanyl patch", ["Duragesic"]),
                 ("hydrocodone", ["Norco", "Vicodin"]), ("methadone", []),
                 ("morphine", ["MS Contin"]), ("oxycodone", ["OxyContin", "Percocet"]),
                 ("tramadol", ["Ultram"])],
              "Opioids", .pain,
              Guidance(action: .takeAsDirected, concern: "Withdrawal"))

        + build([("naltrexone", ["Vivitrol", "Revia"])],
              "Opioid antagonists", .pain,
              Guidance(
                  action: .variable("Depends on dose"),
                  detail: "If prescribed for psychiatric treatment, must consult with prescribing "
                        + "provider to develop a safe stopping and restarting plan.",
                  conditionals: [
                      Conditional("What is the daily dose?", "Low dose (1.5 to 6mg)", .takeAsDirected),
                      Conditional("What is the daily dose?", "High dose (greater than 6mg)", .holdHours(72))
                  ],
                  concern: "Inadequate post-op pain control"))

    // ----------------------------------------------------------------- NSAID

    private static let nsaids: [Drug] = {
        let concern = "Bleeding"
        func n(_ generic: String, _ brands: [String], _ half: Double?, _ action: Action) -> Drug {
            Drug(id: slug(generic), generic: generic, brands: brands,
                 drugClass: "NSAIDs", category: .nsaid,
                 guidance: Guidance(action: action, concern: concern),
                 halfLifeHours: half)
        }
        return [
            n("celecoxib",       ["Celebrex"],          11.2, .takeAsDirected),
            n("diclofenac",      ["Voltaren"],          2.0,  .holdDayOfSurgery),
            n("diclofenac XR",   ["Voltaren XR"],       nil,  .holdHours(24)),
            n("etodolac",        [],                    7.3,  .takeAsDirected),
            n("fenoprofen",      ["Nalfon"],            3.0,  .holdDayOfSurgery),
            n("flurbiprofen",    ["Ansaid"],            5.7,  .holdHours(17)),
            n("ibuprofen",       ["Advil", "Motrin"],   2.0,  .holdDayOfSurgery),
            n("indomethacin",    ["Indocin"],           4.5,  .holdHours(14)),
            n("ketoprofen",      [],                    2.1,  .holdDayOfSurgery),
            n("ketoprofen ER",   [],                    5.4,  .holdHours(16)),
            n("ketorolac",       ["Toradol"],           6.0,  .holdHours(18)),
            n("meclofenamate",   [],                    1.3,  .holdDayOfSurgery),
            n("mefenamic acid",  ["Ponstel"],           2.0,  .holdDayOfSurgery),
            n("meloxicam",       ["Mobic"],             20.0, .takeAsDirected),
            n("nabumetone",      ["Relafen"],           22.5, .takeAsDirected),
            n("naproxen",        ["Naprosyn", "Aleve"], 17.0, .holdHours(48)),
            n("oxaprozin",       ["Daypro"],            50.0, .holdDays(21)),
            n("piroxicam",       ["Feldene"],           50.0, .holdDays(21)),
            n("sulindac",        ["Clinoril"],          7.8,  .holdHours(24)),
            n("tolmetin",        [],                    7.0,  .holdHours(21))
        ]
    }()

    // ----------------------------------------------------------- RESPIRATORY

    private static let respiratory: [Drug] =
        build([("cough assist", []), ("hypertonic saline", []), ("vest therapy", [])],
              "Airway clearance therapies", .respiratory,
              Guidance(action: .takeAsDirected, concern: "Respiratory distress"))

        + build([("albuterol", ["Proventil", "Ventolin"]),
                 ("albuterol/ipratropium", ["Duoneb"]),
                 ("formoterol/budesonide", ["Symbicort"]),
                 ("formoterol/mometasone", ["Dulera"]),
                 ("ipratropium", ["Atrovent"]),
                 ("levalbuterol", ["Xopenex"]),
                 ("salmeterol/fluticasone", ["Advair"])],
              "Bronchodilators", .respiratory,
              Guidance(action: .takeAsDirected, concern: "Respiratory distress"))

        + build([("beclomethasone", ["QVAR"]), ("fluticasone", ["Flovent"]),
                 ("mometasone", ["Asmanex"])],
              "Inhaled corticosteroids", .respiratory,
              Guidance(action: .takeAsDirected, concern: "Respiratory distress"))

    // --------------------------------------------------- RHEUMATOLOGY/IMMUNE

    private static let rheumImmune: [Drug] =
        build([("sulfasalazine", ["Azulfidine"])],
              "DMARDs", .rheumImmune,
              Guidance(action: .takeAsDirected))

        + build([("azathioprine", ["Imuran"]), ("cyclosporine", ["Neoral"]),
                 ("everolimus", ["Afinitor"]), ("mycophenolate", ["Cellcept", "Myfortic"]),
                 ("sirolimus", ["Rapamune"]), ("tacrolimus", ["Prograf"])],
              "Immunosuppressants", .rheumImmune,
              Guidance(action: .takeAsDirected, concern: "Rejection"))

        + build([("probenecid", [])],
              "Uricosuric agents", .rheumImmune,
              Guidance(action: .holdDayOfSurgery,
                       concern: "Interacts with perioperative medications"))

    // ---------------------------------------------------------- RECREATIONAL

    private static let recreational: [Drug] = [
        Drug(id: "alcohol", generic: "alcohol", brands: ["ethanol"],
             drugClass: "Recreational substances", category: .recreational,
             guidance: Guidance(action: .holdHours(48),
                                detail: "Hold at least 48 hours prior to surgery.",
                                concern: "Anesthesia interaction"),
             halfLifeHours: nil),

        Drug(id: "cannabis", generic: "CBD / marijuana", brands: ["cannabis", "THC", "marijuana"],
             drugClass: "Recreational substances", category: .recreational,
             guidance: Guidance(
                 action: .variable("Depends on route and indication"),
                 conditionals: [
                     Conditional("How is it used?", "Inhaled", .holdHours(72),
                                 "Hold at least 72 hours prior to surgery."),
                     Conditional("How is it used?", "Edible", .holdDayOfSurgery),
                     Conditional("How is it used?", "Prescribed for a medical indication", .takeAsDirected)
                 ],
                 concern: "Airway reactivity, hemodynamic instability, increased sedation "
                        + "requirement, postoperative pain"),
             halfLifeHours: nil),

        Drug(id: "nicotine", generic: "nicotine", brands: ["tobacco", "vaping", "e-cigarette"],
             drugClass: "Recreational substances", category: .recreational,
             guidance: Guidance(
                 action: .variable("Depends on route"),
                 conditionals: [
                     Conditional("How is it used?", "Inhaled (smoking or vaping)", .holdDays(7),
                                 "Hold at least 7 days prior to surgery."),
                     Conditional("How is it used?", "Patch", .takeAsDirected)
                 ],
                 concern: "Respiratory compromise"),
             halfLifeHours: nil)
    ]

    // ------------------------------------------------------------ SUPPLEMENTS

    private static let supplements: [Drug] = {
        let defaultHerbal = Guidance(
            action: .holdDays(7),
            detail: "Hold at least 7 days prior to surgery due to risk of interactions with "
                  + "anesthesia medications, increased bleeding, and/or hemodynamic instability.")

        func s(_ generic: String, _ brands: [String], _ concern: String?) -> Drug {
            var g = defaultHerbal
            g.concern = concern
            return Drug(id: slug(generic), generic: generic, brands: brands,
                        drugClass: "Supplements and herbals", category: .supplement,
                        guidance: g, halfLifeHours: nil)
        }

        let holdDOS = Guidance(action: .holdDayOfSurgery,
                               detail: "Hold on day of surgery.")

        return [
            Drug(id: "multivitamin", generic: "multivitamin", brands: ["MVI"],
                 drugClass: "Supplements", category: .supplement,
                 guidance: holdDOS, halfLifeHours: nil),
            Drug(id: "zinc", generic: "zinc", brands: [],
                 drugClass: "Supplements", category: .supplement,
                 guidance: holdDOS, halfLifeHours: nil),
            Drug(id: "iron", generic: "iron", brands: ["ferrous sulfate"],
                 drugClass: "Supplements", category: .supplement,
                 guidance: holdDOS, halfLifeHours: nil),

            Drug(id: "vitaminc", generic: "vitamin C", brands: ["ascorbic acid"],
                 drugClass: "Supplements", category: .supplement,
                 guidance: Guidance(
                     action: .variable("Depends on indication"),
                     conditionals: [
                         Conditional("What is it prescribed for?", "Chronic pain", .takeAsDirected),
                         Conditional("What is it prescribed for?", "General supplementation", .holdDayOfSurgery)
                     ]),
                 halfLifeHours: nil),

            Drug(id: "leucovorin", generic: "leucovorin", brands: ["folinic acid"],
                 drugClass: "Supplements", category: .supplement,
                 guidance: Guidance(
                     action: .variable("Depends on indication"),
                     conditionals: [
                         Conditional("What is it prescribed for?", "Autism", .takeAsDirected),
                         Conditional("What is it prescribed for?", "Other indication", .holdDays(7))
                     ]),
                 halfLifeHours: nil),

            s("ginkgo",         ["gingko", "ginkgo biloba"], "Bleeding"),
            s("garlic",         ["allium"],                  "Bleeding"),
            s("ginseng",        [],                          "Bleeding"),
            s("ephedra",        ["ma huang"],
              "Tachycardia, hypertension, MI, stroke, hemodynamic instability, drug interactions"),
            s("kava",           ["kava kava"],
              "Sedation, potentiation of anesthetic medications, withdrawal, tolerance, addiction"),
            s("saw palmetto",   [],
              "Intra-operative floppy iris syndrome during ophthalmic surgery"),
            s("St. John's wort", ["hypericum"],              "Prolonged anesthesia effects"),
            s("valerian root",  ["valerian"],                "Prolonged anesthesia effects"),
            s("vitamin E",      ["tocopherol"],              "Bleeding due to antiplatelet properties")
        ]
    }()

    // ------------------------------------------------------------------- ALL

    static let all: [Drug] =
        cardiovascular + endocrine + gastrointestinal + hematology
        + neuroBehavioral + pain + nsaids + respiratory + rheumImmune
        + recreational + supplements

    /// Canonical lookup. This is the dedup key for the entire pipeline.
    static let byID: [String: Drug] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { a, _ in a }
    )

    // ------------------------------------------------------- CROSS-DRUG RULES

    /// Potassium-wasting diuretics named in the PARC guideline.
    static let potassiumWastingDiuretics: Set<String> = [
        "budesonide", "chlorthalidone", "ethacrynate", "furosemide",
        "hydrochlorothiazide", "indapamide", "torsemide"
    ]

    static let interactionRules: [InteractionRule] = [
        InteractionRule(
            id: "k-supplement-with-wasting-diuretic",
            triggerID: "potassiumsupplement",
            requiresAnyOf: potassiumWastingDiuretics,
            revisedAction: .holdDayOfSurgery,
            message: "Hold potassium supplement: patient is also on a potassium-wasting diuretic. "
                   + "Risk of hyperkalemia."
        )
    ]

    /// Applies whole-list rules after matching.
    static func applyInteractionRules(to resolved: [Drug]) -> [(rule: InteractionRule, drug: Drug)] {
        let present = Set(resolved.map { $0.id })
        return interactionRules.compactMap { rule in
            guard present.contains(rule.triggerID),
                  !present.isDisjoint(with: rule.requiresAnyOf),
                  let d = byID[rule.triggerID] else { return nil }
            return (rule, d)
        }
    }
}
