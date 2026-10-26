/// 模型引用里的 `#variant` 处理。
///
/// nava 目前只把 `provider/model#variant` 当作可接受的写法：解析时去掉
/// variant 再交给 provider。variant 的请求参数（reasoning effort 等）因
/// provider 而异，暂不自动映射。
library;

/// 去掉 `#variant` 后缀；没有时原样返回。
String stripModelVariant(String model) {
  final int hash = model.indexOf('#');
  return hash > 0 ? model.substring(0, hash) : model;
}

/// 提取 `#variant`；没有时返回 `null`。
String? modelVariant(String model) {
  final int hash = model.indexOf('#');
  if (hash <= 0 || hash == model.length - 1) return null;
  return model.substring(hash + 1);
}
