import json, os, re, sys

MAP = json.load(open(sys.argv[1]))
OUT = sys.argv[2]

# Java class name -> Swift type name (avoids clashes with Swift stdlib / clarifies intent)
RENAME = {
    "Collection": "ReleaseCollection",
    "Type": "EpisodeType",
    "Source": "EpisodeSource",
    "CollectionCompact": "ReleaseCollectionCompact",
    "Theme": "ProfileTheme",
}
# Back-references that would create an Optional-only recursive value type (illegal in Swift),
# or that the API never returns (Room relations in the Android app).
DROP = {
    ("Episode", "release"),
    ("Release", "lastSetCompletedDate"), ("Release", "lastSetDroppedDate"),
    ("Release", "lastSetFavoriteDate"), ("Release", "lastSetHoldOnDate"),
    ("Release", "lastSetPlanDate"), ("Release", "lastSetViewedDate"),
    ("Release", "lastSetWatchingDate"),
    ("Episode", "source"),
    ("ReleaseStreamingPlatform", "release"),
    ("Search", "type"),
    # Room row ids the server never sends. Keeping them as a required `id` failed
    # the whole response ("missing key 'id'"), which is what broke the episode
    # list and the profile. Both types get a hand-written Identifiable keyed on
    # what the server does send -- see Models/RoomEntities.swift.
    ("Episode", "id"), ("ProfileWatchDynamics", "id"),
}
# Explicit Swift type overrides for props whose Java type we can't map mechanically.
TYPE_OVERRIDE = {
    ("Article", "payload"): "ArticlePayload",
    # An indirect enum breaks the Optional-only recursion of a repost.
    ("Article", "repostArticle"): "ArticleReference",
    ("ReleaseVideo", "release"): "Embedded<Release>",
    ("Profile", "commentsPreview"): "[ProfileComment]",
    ("Profile", "roles"): "[RoleDto]",
    ("ConfigUrlsResponse", "apiUrls"): "[String]",
    ("TypeResponse", "popularTypeIds"): "[Int]",
    # Jackson maps this Java enum from either its name or its ordinal; FriendStatusCode
    # decodes both. See Models/FriendStatusCode.swift.
    ("Profile", "friendStatus"): "FriendStatusCode",
    ("ReleaseComment", "profile"): "ProfileCompact",
    # Relations the server sends either as the whole object or as a bare row id,
    # depending on the endpoint. See Models/Embedded.swift.
    ("ReleaseComment", "release"): "Embedded<Release>",
    ("Source", "type"): "Embedded<EpisodeType>",   # Source is renamed to EpisodeSource
    ("CollectionComment", "profile"): "ProfileCompact",
}

# Types whose decoder coerces scalars instead of trusting the JSON type.
#
# The config responses are grab-bags of flags edited by hand on the server, and
# it already sends `searchBarIconTint` as the string "false" among two dozen real
# booleans. The synthesised init turned that one field into a failure of the
# whole response, so the app silently lost `kodikAdIframeUrl` with it. See
# Networking/LooseScalars.swift.
LENIENT = {"TogglesResponse", "ConfigUrlsResponse"}

# Swift type -> the loose accessor that reads it.
LOOSE = {
    "Bool": "looseBool",
    "Int": "looseInt",
    "Double": "looseDouble",
    "String": "looseString",
    "[String]": "looseStrings",
}

PRIM = {
    "long": "Int", "Long": "Int", "int": "Int", "Integer": "Int",
    "short": "Int", "byte": "Int",
    "double": "Double", "Double": "Double", "float": "Double", "Float": "Double",
    "boolean": "Bool", "Boolean": "Bool",
    "String": "String", "CharSequence": "String",
}

SWIFT_KEYWORDS = {
    "class","struct","enum","protocol","extension","func","var","let","if","else","for","while",
    "repeat","switch","case","default","break","continue","return","in","is","as","try","catch",
    "throw","throws","guard","where","self","Self","super","init","deinit","subscript","operator",
    "import","typealias","associatedtype","inout","static","public","private","internal","fileprivate",
    "open","final","lazy","weak","unowned","nil","true","false","do","defer","some","any","Type",
}

def swift_type(java, cls, prop):
    ov = TYPE_OVERRIDE.get((cls, prop))
    if ov:
        return ov
    java = java.strip()
    m = re.match(r'(?:List|Set|LinkedHashSet|ArrayList|HashSet|Collection)<(.+)>$', java)
    if m:
        inner = m.group(1).strip().replace("? extends ", "").strip()
        it = swift_type(inner, cls, prop)
        return None if it is None else "[%s]" % it
    m = re.match(r'(?:Map|HashMap|LinkedHashMap)<', java)
    if m:
        return "[String: String]"
    m = re.match(r'(\w+)<(.+)>$', java)          # e.g. PageableResponse<Article>
    if m:
        outer = RENAME.get(m.group(1), m.group(1))
        inner = swift_type(m.group(2).strip().replace("? extends ", ""), cls, prop)
        return None if inner is None else "%s<%s>" % (outer, inner)
    if java in PRIM:
        return PRIM[java]
    java = java.split(".")[-1]
    if java in PRIM:
        return PRIM[java]
    if not re.match(r'^[A-Z]\w*$', java):
        return None
    return RENAME.get(java, java)

def swift_name(prop):
    n = prop
    if n in SWIFT_KEYWORDS:
        return "`%s`" % n
    return n

def gen(cls, emit_name=None, extra_parents=()):
    info = MAP[cls]
    name = emit_name or RENAME.get(cls, cls)
    props = []
    seen = set()
    # inherited props first (e.g. ReleaseComment extends Comment<ProfileCompact>)
    chain = list(extra_parents)
    for pcls in chain:
        for p in MAP[pcls]["props"]:
            if not p["hasField"] or (cls, p["prop"]) in DROP or p["prop"] in seen:
                continue
            seen.add(p["prop"]); props.append((pcls, p))
    for p in info["props"]:
        if not p["hasField"] or (cls, p["prop"]) in DROP or p["prop"] in seen:
            continue
        seen.add(p["prop"]); props.append((cls, p))

    rows, skipped = [], []
    for owner, p in props:
        st = swift_type(p["type"], cls, p["prop"])
        if st is None:
            skipped.append((p["prop"], p["type"])); continue
        rows.append((swift_name(p["prop"]), st, p["json"], p["prop"]))

    is_response = info.get("parent") == "Response" or any(MAP[x].get("parent") == "Response" for x in chain)
    has_id = any(r[3] == "id" for r in rows)

    L = []
    L.append("// Generated from Anixart %s (com.swiftsoft.anixartd.%s).\n// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.\n// Do not edit by hand -- see Tools/generate-models.py in the repo root." % (cls, info["file"].replace("/", ".").replace(".java", "")))
    L.append("")
    L.append("import Foundation")
    L.append("")
    protos = ["Codable", "Hashable", "Sendable"]
    if has_id:
        protos.append("Identifiable")
    L.append("public struct %s: %s {" % (name, ", ".join(protos)))
    if is_response:
        L.append("    /// Anixart status code. `0` is success; see `AnixartStatus`.")
        L.append("    public var code: Int?")
    for sn, st, jk, raw in rows:
        if raw == "id" and has_id:
            # A server-assigned id is always present, so keeping it non-optional makes
            # these usable with SwiftUI's ForEach and turns a malformed payload into a
            # loud decode failure instead of a silent nil that collides with every
            # other nil. A Room row id is NOT server-assigned -- those are in DROP.
            L.append("    public var %s: %s" % (sn, st))
        else:
            L.append("    public var %s: %s?" % (sn, st))
    L.append("")
    L.append("    public enum CodingKeys: String, CodingKey {")
    if is_response:
        L.append('        case code')
    for sn, st, jk, raw in rows:
        if jk == raw:
            L.append("        case %s" % sn)
        else:
            L.append('        case %s = "%s"' % (sn, jk))
    L.append("    }")
    L.append("}")
    if name in LENIENT:
        # In an extension, not the body: an initialiser in the body would take
        # the memberwise `init()` away with it, and these are built by hand in
        # the tests and in `AnixartClient.apply`.
        L.append("")
        L.append("// Hand-rolled rather than synthesised, so that one mistyped flag costs that")
        L.append("// flag and not the whole response. See LENIENT in Tools/generate-models.py")
        L.append("// and Networking/LooseScalars.swift.")
        L.append("extension %s {" % name)
        L.append("    public init(from decoder: any Decoder) throws {")
        L.append("        let c = try decoder.container(keyedBy: CodingKeys.self)")
        L.append("        self.init()")
        if is_response:
            L.append("        code = c.looseInt(.code)")
        for sn, st, jk, raw in rows:
            accessor = LOOSE.get(st)
            if accessor is None:
                raise SystemExit(
                    "!! %s.%s is %s; LooseScalars has no accessor for it" % (name, sn, st)
                )
            L.append("        %s = c.%s(.%s)" % (sn, accessor, sn.strip("`")))
        L.append("    }")
        L.append("}")
    if skipped:
        L.append("")
        L.append("// Props omitted (unmapped Java type): " + ", ".join("%s: %s" % s for s in skipped))
    return name, "\n".join(L) + "\n"

CURATED = [
    # core catalogue
    ("Release", None, ()), ("ReleaseStatus", None, ()), ("Category", None, ()), ("Genre", None, ()),
    ("Related", None, ()), ("EpisodeUpdate", None, ()),
    ("Episode", None, ()), ("Type", None, ()), ("Source", None, ()),
    ("EpisodeCompact", None, ()), ("LastWatchedEpisode", None, ()),
    ("ReleaseStreamingPlatform", None, ()), ("ReleaseVideoBanner", None, ()),
    ("ProfileReleaseTypeNotificationPreference", None, ()),
    ("Interesting", None, ()),
    # profiles
    ("Profile", None, ()), ("ProfileToken", None, ()), ("ProfileCompact", None, ()),
    ("ProfileSlim", None, ()), ("RoleDto", None, ()), ("ProfileGenre", None, ()),
    ("ProfileWatchDynamics", None, ()), ("Badge", None, ()), ("BadgeAward", None, ()),
    ("ChangeLogin", None, ()), ("BadgeSection", None, ()),
    ("AvailableTheme", None, ()), ("Theme", None, ()),
    # ProfileEnforcement is hand-written: Jackson's `type` discriminator and
    # generic EditEnforcement.entity are not part of this annotation-only map.
    # collections, comments, social
    ("Collection", None, ()), ("ReleaseComment", None, ("Comment",)),
    ("CollectionComment", None, ("Comment",)),
    ("Channel", None, ()), ("Article", None, ()), ("ReleaseVideo", None, ()),
    ("Vote", None, ()), ("Search", None, ()),
    ("PopularComment", None, ()), ("BadgeCategory", None, ()),
    ("ReleaseCompact", None, ()), ("SourceCompact", None, ()), ("TypeCompact", None, ()),
    ("ReleaseVideoCategory", None, ()), ("ReleaseVideoHosting", None, ()),
    # responses
    ("ReleaseResponse", None, ()), ("ReleaseSearchResponse", None, ()),
    ("TypesResponse", None, ()), ("SourcesResponse", None, ()), ("EpisodeResponse", None, ()),
    ("TypeResponse", None, ()), ("ScheduleResponse", None, ()),
    ("SignInResponse", None, ()), ("SignUpResponse", None, ()), ("VerifyResponse", None, ()),
    ("VkResponse", None, ()), ("GoogleResponse", None, ()), ("TelegramResponse", None, ()),
    ("YandexResponse", None, ()), ("RestoreResponse", None, ()), ("RestoreVerifyResponse", None, ()),
    ("ProfileResponse", None, ()), ("CollectionResponse", None, ()),
    ("ProfilePreferenceResponse", None, ()), ("ProfileBadgeSectionsResponse", None, ()),
    ("ProfileSelectThemeResponse", None, ()),
    ("ChangeLoginInfoResponse", None, ()), ("ChangeLoginResponse", None, ()),
    ("CheckLoginResponse", None, ()), ("ProfileBadgeResponse", None, ()),
    ("ChangeEmailResponse", None, ()), ("ChangeEmailResendResponse", None, ()),
    ("ChangePasswordResponse", None, ()), ("ProfileDeletionResponse", None, ()),
    ("ProfileHealthStatusResponse", None, ()), ("ProfileEnforcementResponse", None, ()),
    ("ChannelResponse", None, ()), ("ChannelUploadCoverAvatarResponse", None, ()),
    ("FavoritesResponse", None, ()), ("HistoryResponse", None, ()),
    ("VoteReleaseResponse", None, ()), ("DeleteVoteReleaseResponse", None, ()),
    ("ConfigUrlsResponse", None, ()), ("TogglesResponse", None, ()),
]

os.makedirs(OUT, exist_ok=True)
made = []
for cls, nm, parents in CURATED:
    if cls not in MAP:
        print("!! missing in map:", cls); continue
    for p in parents:
        if p not in MAP:
            print("!! missing parent:", p); continue
    name, src = gen(cls, nm, parents)
    open(os.path.join(OUT, name + ".swift"), "w", encoding="utf-8", newline="\n").write(src)
    made.append(name)
print("generated %d types:" % len(made))
print("  " + ", ".join(sorted(made)))
