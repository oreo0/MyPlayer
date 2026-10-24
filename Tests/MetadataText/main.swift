import Foundation
func check(_ actual: String, _ expected: String) { precondition(actual == expected, "\(actual) != \(expected)") }
check(MetadataText.repaired("·èÓïÕß (Going Crazy)"), "疯语者 (Going Crazy)")
check(MetadataText.repaired("¿É°®¡¤¿É¶ñ (What U do?)"), "可爱·可恶 (What U do?)")
check(MetadataText.repaired("ÃÎ»ØÄºÒ¹ (Walk On Memories)"), "梦回暮夜 (Walk On Memories)")
check(MetadataText.repaired("CÀÖÕÂ (Diamond)"), "C乐章 (Diamond)")
check(MetadataText.repaired("Beyoncé"), "Beyoncé")
check(MetadataText.repaired("宝船"), "宝船")
check(MetadataText.repaired("Why?"), "Why?")
check(MetadataText.title("?? ?? (Going Crazy)", path: "/Music/내가 미쳐 (Going Crazy)-EXO.mp3", artist: "EXO"), "내가 미쳐 (Going Crazy)")
check(MetadataText.title("?? (Ç°Ò¹) (The Eve)", path: "/Music/전야 (前夜) (The Eve)-EXO 2.mp3", artist: "EXO"), "전야 (前夜) (The Eve)")
print("PASS: reversible GBK repair, Unicode filename fallback, artist suffix removal, and normal metadata preservation")
