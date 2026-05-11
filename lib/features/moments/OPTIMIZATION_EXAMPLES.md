# 性能优化代码示例

## 1. 优化 Provider 监听（P0 - 最高优先级）

### ❌ 当前代码 (moments_page.dart:153)
```dart
@override
Widget build(BuildContext context) {
  super.build(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final momentState = ref.watch(momentProvider); // ❌ 监听整个状态
  
  // ...
}
```

### ✅ 优化后代码
```dart
@override
Widget build(BuildContext context) {
  super.build(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  // ✅ 只监听需要的部分，避免不必要的重建
  final moments = ref.watch(momentProvider.select((state) => state.moments));
  final isLoading = ref.watch(momentProvider.select((state) => state.isLoading));
  final isLoadingMore = ref.watch(momentProvider.select((state) => state.isLoadingMore));
  final hasMore = ref.watch(momentProvider.select((state) => state.hasMore));
  
  // ...
  
  // 使用优化后的变量
  if (moments.isEmpty && !isLoading)
    // ...
  
  SliverMasonryGrid.count(
    childCount: moments.length,
    itemBuilder: (context, index) {
      final moment = moments[index];
      // ...
    },
  ),
  
  _buildLoadMoreIndicator(isLoadingMore, hasMore, moments.isNotEmpty, isDark),
}
```

**效果**: 当只有 `isLoading` 或 `isLoadingMore` 变化时，不会重建整个列表。

---

## 2. 为列表项添加 key（P0 - 最高优先级）

### ❌ 当前代码 (moments_page.dart:210-219)
```dart
itemBuilder: (context, index) {
  final moment = momentState.moments[index];
  return _WaterfallMomentCard(
    moment: moment,
    isDark: isDark,
    onLike: () => ref.read(momentProvider.notifier).toggleLike(moment.id),
    onTap: () => _openMomentDetail(moment),
    onLongPress: (details, ctx) => _showCardPopupMenu(ctx, details.globalPosition, moment),
  );
}
```

### ✅ 优化后代码
```dart
itemBuilder: (context, index) {
  final moment = moments[index];
  return RepaintBoundary( // ✅ 隔离重绘
    key: ValueKey(moment.id), // ✅ 添加 key，帮助 Flutter 识别和复用 widget
    child: _WaterfallMomentCard(
      key: ValueKey(moment.id), // ✅ 双重保护
      moment: moment,
      isDark: isDark,
      onLike: () => _handleLike(moment.id), // ✅ 使用类方法
      onTap: () => _openMomentDetail(moment),
      onLongPress: (details, ctx) => _showCardPopupMenu(ctx, details.globalPosition, moment),
    ),
  );
}

// ✅ 将回调提取为类方法，避免每次创建新函数
void _handleLike(String momentId) {
  ref.read(momentProvider.notifier).toggleLike(momentId);
}
```

**效果**: Flutter 可以正确识别列表项，减少不必要的重建。

---

## 3. 优化图片加载（P1 - 重要）

### ❌ 当前代码 (moments_page.dart:1221-1232)
```dart
CachedNetworkImage(
  imageUrl: imageUrl,
  fit: BoxFit.cover,
  placeholder: (context, url) => placeholder,
  errorWidget: (context, url, error) => Container(...),
  memCacheWidth: 320,
  memCacheHeight: 400,
  fadeInDuration: const Duration(milliseconds: 150),
)
```

### ✅ 优化后代码
```dart
RepaintBoundary( // ✅ 隔离图片重绘
  child: CachedNetworkImage(
    imageUrl: imageUrl,
    fit: BoxFit.cover,
    placeholder: (context, url) => placeholder,
    errorWidget: (context, url, error) => Container(...),
    // ✅ 内存缓存：根据设备像素比优化
    memCacheWidth: (320 * MediaQuery.of(context).devicePixelRatio).round(),
    memCacheHeight: (400 * MediaQuery.of(context).devicePixelRatio).round(),
    // ✅ 磁盘缓存：限制大小，避免无限增长
    maxWidthDiskCache: 800,
    maxHeightDiskCache: 1000,
    fadeInDuration: const Duration(milliseconds: 150),
    // ✅ 缓存 key：使用 moment.id 作为缓存 key，便于管理
    cacheKey: 'moment_${moment.id}_${imageUrl}',
  ),
)
```

**效果**: 
- 图片加载不会影响其他组件
- 磁盘缓存可控
- 内存使用更合理

---

## 4. 优化 _WaterfallMomentCard 组件（P1 - 重要）

### ❌ 当前代码 (moments_page.dart:1054-1200)
```dart
@override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: widget.onTap,
    // ...
  );
}
```

### ✅ 优化后代码
```dart
@override
Widget build(BuildContext context) {
  return RepaintBoundary( // ✅ 隔离卡片重绘
    child: GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        widget.onLongPress(details, context);
      },
      child: Stack(
        children: [
          Container(
            // ... 卡片内容
          ),
          // 点赞动画
          if (_showLikeAnimation)
            // ... 动画内容
        ],
      ),
    ),
  );
}

Widget _buildCoverImage() {
  // ... 
  return RepaintBoundary( // ✅ 图片单独隔离
    child: AspectRatio(
      aspectRatio: 0.8,
      child: Stack(
        children: [
          CachedNetworkImage(
            // ... 优化后的图片配置
          ),
        ],
      ),
    ),
  );
}
```

**效果**: 卡片内部的变化不会影响其他卡片。

---

## 5. 优化 Provider 状态更新（P2 - 可选）

### ❌ 当前代码 (moment_provider.dart:618-628)
```dart
Future<void> toggleLike(String momentId) async {
  // ...
  // ❌ 创建整个新列表
  state = state.copyWith(
    moments: state.moments.map((m) {
      if (m.id == momentId) {
        return m.copyWith(
          isLiked: !wasLiked,
          likeCount: wasLiked ? m.likeCount - 1 : m.likeCount + 1,
        );
      }
      return m;
    }).toList(),
  );
}
```

### ✅ 优化后代码（使用 freezed）
```dart
// 1. 使用 freezed 定义状态
@freezed
class MomentState with _$MomentState {
  const factory MomentState({
    required List<Moment> moments,
    // ...
  }) = _MomentState;
}

// 2. 优化更新逻辑
Future<void> toggleLike(String momentId) async {
  // ...
  // ✅ 只更新变化的项，其他项保持引用不变
  final index = state.moments.indexWhere((m) => m.id == momentId);
  if (index == -1) return;
  
  final updatedMoments = List<Moment>.from(state.moments);
  updatedMoments[index] = updatedMoments[index].copyWith(
    isLiked: !wasLiked,
    likeCount: wasLiked ? updatedMoments[index].likeCount - 1 
                        : updatedMoments[index].likeCount + 1,
  );
  
  state = state.copyWith(moments: updatedMoments);
}
```

**效果**: 只有变化的项会重建，其他项保持引用不变。

---

## 6. 缓存 isDark 值（P2 - 可选）

### ❌ 当前代码
```dart
@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // 每次 build 都重新计算
}
```

### ✅ 优化后代码
```dart
class _MomentsPageState extends ConsumerState<MomentsPage> 
    with AutomaticKeepAliveClientMixin {
  
  bool? _cachedIsDark;
  
  bool _getIsDark(BuildContext context) {
    final currentIsDark = Theme.of(context).brightness == Brightness.dark;
    if (_cachedIsDark != currentIsDark) {
      _cachedIsDark = currentIsDark;
    }
    return _cachedIsDark ?? false;
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = _getIsDark(context);
    // ...
  }
}
```

**效果**: 减少重复计算（虽然影响很小）。

---

## 7. 完整的优化后的 build 方法示例

```dart
@override
Widget build(BuildContext context) {
  super.build(context);
  
  // ✅ 使用 select 只监听需要的部分
  final moments = ref.watch(momentProvider.select((state) => state.moments));
  final isLoading = ref.watch(momentProvider.select((state) => state.isLoading));
  final isLoadingMore = ref.watch(momentProvider.select((state) => state.isLoadingMore));
  final hasMore = ref.watch(momentProvider.select((state) => state.hasMore));
  
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final topPadding = MediaQuery.of(context).padding.top;
  
  return Scaffold(
    backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
    body: Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await ref.read(momentProvider.notifier).refresh();
          },
          edgeOffset: topPadding + 70,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: topPadding + 70),
              ),
              
              if (moments.isEmpty && !isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无动态',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childCount: moments.length,
                    itemBuilder: (context, index) {
                      final moment = moments[index];
                      return RepaintBoundary(
                        key: ValueKey('moment_${moment.id}'),
                        child: _WaterfallMomentCard(
                          key: ValueKey(moment.id),
                          moment: moment,
                          isDark: isDark,
                          onLike: () => _handleLike(moment.id),
                          onTap: () => _openMomentDetail(moment),
                          onLongPress: (details, ctx) => 
                            _showCardPopupMenu(ctx, details.globalPosition, moment),
                        ),
                      );
                    },
                  ),
                ),
              
              SliverToBoxAdapter(
                child: _buildLoadMoreIndicator(isLoadingMore, hasMore, moments.isNotEmpty, isDark),
              ),
              
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        ),
        
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
            child: _buildTopBar(isDark),
          ),
        ),
      ],
    ),
  );
}

// ✅ 提取回调方法
void _handleLike(String momentId) {
  ref.read(momentProvider.notifier).toggleLike(momentId);
}
```

---

## 实施建议

1. **分步实施**: 先实施 P0 优先级优化（Provider select 和 key），测试效果
2. **性能测试**: 使用 Flutter DevTools 的 Performance 面板验证
3. **真实设备测试**: 在低端设备上测试滚动流畅度
4. **监控指标**: 
   - 滚动 FPS（目标：60 FPS）
   - 内存使用（目标：稳定，不增长）
   - 重建次数（目标：减少 60-80%）
