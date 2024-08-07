import 'package:app_rhyme/desktop/comps/navigation_column.dart';
import 'package:app_rhyme/desktop/pages/online_music_container_listview_page.dart';
import 'package:app_rhyme/src/rust/api/cache/music_cache.dart'
    as rust_api_music_cache;
import 'package:app_rhyme/utils/cache_helper.dart';
import 'package:app_rhyme/utils/global_vars.dart';
import 'package:app_rhyme/utils/log_toast.dart';
import 'package:app_rhyme/dialogs/music_container_dialog.dart';
import 'package:app_rhyme/dialogs/musiclist_info_dialog.dart';
import 'package:app_rhyme/dialogs/select_local_music_dialog.dart';
import 'package:app_rhyme/mobile/pages/online_music_list_page.dart';
import 'package:app_rhyme/src/rust/api/bind/factory_bind.dart';
import 'package:app_rhyme/src/rust/api/bind/mirrors.dart';
import 'package:app_rhyme/src/rust/api/bind/type_bind.dart';
import 'package:app_rhyme/types/music_container.dart';
import 'package:app_rhyme/utils/const_vars.dart';
import 'package:app_rhyme/utils/refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

Future<void> deleteMusicsFromLocalMusicList(BuildContext context,
    List<MusicContainer> musicContainers, MusicListW musicListW) async {
  try {
    await SqlFactoryW.delMusics(
        musicListName: musicListW.getMusiclistInfo().name,
        ids:
            Int64List.fromList(musicContainers.map((e) => e.info.id).toList()));
    refreshMusicContainerListViewPage();
  } catch (e) {
    LogToast.error("删除音乐失败", "删除音乐失败: $e",
        "[deleteMusicsFromMusicList] Failed to delete music: $e");
  }
}

Future<void> delMusicCache(MusicContainer musicContainer,
    {bool showToast = true, bool showToastWhenNoMsuicCache = false}) async {
  // 这个函数运行耗时短，连续使用时应showToast = false
  try {
    bool hasCache = await musicContainer.hasCache();
    if (!hasCache) {
      if (showToastWhenNoMsuicCache && showToast) {
        LogToast.error("删除缓存失败", "音乐没有缓存",
            "[deleteMusicCache] Failed to delete cache: music has no cache");
      }
      return;
    }
    await rust_api_music_cache.deleteMusicCache(musicInfo: musicContainer.info);
    refreshMusicContainerListViewPage();
    if (showToast) {
      LogToast.success("删除缓存成功", "成功删除缓存: ${musicContainer.info.name}",
          "[deleteMusicCache] Successfully deleted cache: ${musicContainer.info.name}");
    }
  } catch (e) {
    // 失败时总是要显示toast
    LogToast.error("删除缓存失败", "删除缓存'${musicContainer.info.name}'失败: $e",
        "[deleteMusicCache] Failed to delete cache: $e");
  }
}

Future<void> cacheMusic(MusicContainer musicContainer) async {
  try {
    var success = await musicContainer.updateAll();
    if (!success || musicContainer.playInfo == null) {
      return;
    }
    await rust_api_music_cache.cacheMusic(
        musicInfo: musicContainer.info, playinfo: musicContainer.playInfo!);
    refreshMusicContainerListViewPage();
    LogToast.success("缓存成功", "成功缓存: ${musicContainer.info.name}",
        "[cacheMusic] Successfully cached: ${musicContainer.info.name}");
  } catch (e) {
    LogToast.error("缓存失败", "缓存'${musicContainer.info.name}'失败: $e",
        "[cacheMusic] Failed to cache: $e");
  }
}

Future<void> editMusicInfo(
    BuildContext context, MusicContainer musicContainer) async {
  try {
    var musicInfo = await showMusicInfoDialog(context,
        defaultMusicInfo: musicContainer.info);
    if (musicInfo == null) {
      return;
    }
    await SqlFactoryW.changeMusicInfo(
        musics: [musicContainer.currentMusic], newInfos: [musicInfo]);
    LogToast.success(
        "编辑成功", "编辑音乐信息成功", "[editMusicInfo] Successfully edited music info");
    refreshMusicContainerListViewPage();
  } catch (e) {
    LogToast.error("编辑失败", "编辑音乐信息失败: $e",
        "[editMusicInfo] Failed to edit music info: $e");
  }
}

Future<void> viewMusicAlbum(
    BuildContext context, MusicContainer musicContainer, bool isDesktop) async {
  try {
    var result =
        await musicContainer.currentMusic.fetchAlbum(page: 1, limit: 30);
    var musicList = result.$1;
    var aggs = result.$2;
    if (context.mounted) {
      if (isDesktop) {
        globalSetNavItemSelected("");
        globalNavigatorToPage(DesktopOnlineMusicListPage(
          musicList: musicList,
          firstPageMusicAggregators: aggs,
        ));
      } else {
        Navigator.of(context).push(
          CupertinoPageRoute(
              builder: (context) => MobileOnlineMusicListPage(
                    musicList: musicList,
                    firstPageMusicAggregators: aggs,
                  )),
        );
      }
    }
  } catch (e) {
    LogToast.error(
        "查看专辑失败", "查看专辑失败: $e", "[viewAlbum] Failed to view album: $e");
  }
}

Future<void> addMusicsToMusicList(
    BuildContext context, List<MusicContainer> musicContainers,
    {MusicListInfo? musicListinfo}) async {
  MusicListInfo? targetMusicList;
  if (musicListinfo != null) {
    targetMusicList = musicListinfo;
  } else {
    targetMusicList =
        (await showMusicListSelectionDialog(context))?.getMusiclistInfo();
  }
  if (targetMusicList != null) {
    try {
      if (globalConfig.savePicWhenAddMusicList) {
        for (var musicContainer in musicContainers) {
          var pic = musicContainer.info.artPic;
          if (pic != null && pic.isNotEmpty) {
            try {
              cacheFileHelper(pic, picCacheRoot);
            } catch (_) {}
          }
        }
      }
      try {
        await Future.wait(musicContainers.map((musicContainer) async {
          if (globalConfig.saveLyricWhenAddMusicList) {
            await musicContainer.aggregator.fetchLyric();
          }
        }));
      } catch (_) {
        // LogToast.error(
        //     "添加音乐", "获取歌词失败: $e", "[addToMusicList] Failed to get lyric: $e");
      }
      await SqlFactoryW.addMusics(
          musicsListName: targetMusicList.name,
          musics: musicContainers.map((e) => e.aggregator.clone()).toList());
      refreshMusicContainerListViewPage();

      LogToast.success("添加成功", "成功添加音乐到: ${targetMusicList.name}",
          "[addToMusicList] Successfully added musics to: ${targetMusicList.name}");
    } catch (e) {
      LogToast.error(
          "添加失败", "添加音乐失败: $e", "[addToMusicList] Failed to add music: $e");
    }
  }
}

Future<void> createNewMusicListFromMusics(
    BuildContext context, List<MusicContainer> musicContainers) async {
  if (musicContainers.isEmpty) {
    return;
  }
  var newMusicListInfo = await showMusicListInfoDialog(context,
      defaultMusicList: MusicListInfo(
          id: 0,
          name: musicContainers.first.info.artist.join(","),
          artPic: musicContainers.first.info.artPic ?? "",
          desc: ""));
  if (newMusicListInfo == null) {
    return;
  }
  if (newMusicListInfo.artPic.isNotEmpty) {
    cacheFileHelper(newMusicListInfo.artPic, picCacheRoot);
  }
  try {
    await SqlFactoryW.createMusiclist(musicListInfos: [newMusicListInfo]);
    refreshMusicListGridViewPage();
    if (context.mounted) {
      LogToast.success("创建成功", "成功创建新歌单: ${newMusicListInfo.name}, 正在添加音乐",
          "[createNewMusicList] Successfully created new music list: ${newMusicListInfo.name}, adding musics");
      await addMusicsToMusicList(context, musicContainers,
          musicListinfo: newMusicListInfo);
    } else {
      await SqlFactoryW.delMusiclist(musiclistNames: [newMusicListInfo.name]);
      LogToast.error("创建失败", "创建歌单失败: context is not mounted",
          "[createNewMusicList] Failed to create music list: context is not mounted");
    }
  } catch (e) {
    LogToast.error("创建失败", "创建歌单失败: $e",
        "[createNewMusicList] Failed to create music list: $e");
  }
}

Future<void> setMusicPicAsMusicListCover(
    MusicContainer musicContainer, MusicListW musicListW) async {
  var picLink = musicContainer.info.artPic;
  if (picLink == null || picLink.isEmpty) {
    LogToast.error("设置封面失败", "歌曲没有封面",
        "[setAsMusicListCover] Failed to set cover: music has no cover");
    return;
  }
  var oldMusicListInfo = musicListW.getMusiclistInfo();
  var newMusicListInfo = MusicListInfo(
    name: oldMusicListInfo.name,
    desc: oldMusicListInfo.desc,
    artPic: picLink,
    id: 0,
  );
  try {
    await SqlFactoryW.changeMusiclistInfo(
        old: [oldMusicListInfo], new_: [newMusicListInfo]);
    refreshMusicContainerListViewPage();
    refreshMusicListGridViewPage();
    LogToast.success(
        "设置封面成功", "成功设置为封面", "[setAsMusicListCover] Successfully set as cover");
  } catch (e) {
    LogToast.error("设置封面失败", "设置封面失败: $e",
        "[setAsMusicListCover] Failed to set cover: $e");
  }
}

Future<void> saveMusicList(
    MusicListW musicList, MusicListInfo targetMusicListInfo) async {
  LogToast.success("保存歌单", "正在获取歌单'${musicList.getMusiclistInfo().name}'数据，请稍等",
      "[OnlineMusicListItemsPullDown] Start to save music list");
  try {
    if (targetMusicListInfo.artPic.isNotEmpty) {
      cacheFileHelper(targetMusicListInfo.artPic, picCacheRoot);
    }
    await SqlFactoryW.createMusiclist(musicListInfos: [targetMusicListInfo]);
    refreshMusicListGridViewPage();
    var aggs = await musicList.fetchAllMusicAggregators(
        pagesPerBatch: 5,
        limit: 50,
        withLyric: globalConfig.saveLyricWhenAddMusicList);
    if (globalConfig.savePicWhenAddMusicList) {
      for (var agg in aggs) {
        var pic = agg.getDefaultMusic().getMusicInfo().artPic;
        if (pic != null && pic.isNotEmpty) {
          cacheFileHelper(pic, picCacheRoot);
        }
      }
    }
    await SqlFactoryW.addMusics(
        musicsListName: targetMusicListInfo.name, musics: aggs);
    refreshMusicListGridViewPage();
    LogToast.success("保存歌单", "保存歌单'${targetMusicListInfo.name}'成功",
        "[OnlineMusicListItemsPullDown] Succeed to save music list '${targetMusicListInfo.name}'");
  } catch (e) {
    LogToast.error("保存歌单", "保存歌单'${targetMusicListInfo.name}'失败: $e",
        "[OnlineMusicListItemsPullDown] Failed to save music list '${targetMusicListInfo.name}': $e");
  }
}

Future<void> addAggsOfMusicListToTargetMusicList(
  MusicListW musicList,
  MusicListInfo targetMusicListInfo,
) async {
  var musicListInfo = musicList.getMusiclistInfo();
  LogToast.info("添加歌曲", "正在获取歌单'${musicListInfo.name}'数据，请稍等",
      "[OnlineMusicListItemsPullDown] Start to add music");
  try {
    var aggs = await musicList.fetchAllMusicAggregators(
        pagesPerBatch: 5,
        limit: 50,
        withLyric: globalConfig.saveLyricWhenAddMusicList);
    if (globalConfig.savePicWhenAddMusicList) {
      for (var agg in aggs) {
        var pic = agg.getDefaultMusic().getMusicInfo().artPic;
        if (pic != null && pic.isNotEmpty) {
          cacheFileHelper(pic, picCacheRoot);
        }
      }
    }
    await SqlFactoryW.addMusics(
        musicsListName: targetMusicListInfo.name, musics: aggs);
    refreshMusicContainerListViewPage();
    LogToast.success(
        "添加歌曲",
        "添加歌单'${musicListInfo.name}'中的歌曲到'${targetMusicListInfo.name}'成功",
        "[OnlineMusicListItemsPullDown] Succeed to add music from '${musicListInfo.name}' to '${targetMusicListInfo.name}'");
  } catch (e) {
    LogToast.error(
        "添加歌曲",
        "添加歌单'${musicListInfo.name}'中的歌曲到'${targetMusicListInfo.name}'失败: $e",
        "[OnlineMusicListItemsPullDown] Failed to add music from '${musicListInfo.name}' to '${targetMusicListInfo.name}': $e");
  }
}

Future<void> editMusicListInfo(
    BuildContext context, MusicListW musicList) async {
  var newMusicListInfo = await showMusicListInfoDialog(context,
      defaultMusicList: musicList.getMusiclistInfo(), readonly: false);
  if (newMusicListInfo != null) {
    try {
      await SqlFactoryW.changeMusiclistInfo(
          old: [musicList.getMusiclistInfo()], new_: [newMusicListInfo]);
      refreshMusicListGridViewPage();
      refreshMusicContainerListViewPage();
      LogToast.success("编辑歌单", "编辑歌单成功",
          "[LocalMusicListItemsPullDown] Succeed to edit music list");
    } catch (e) {
      LogToast.error("编辑歌单", "编辑歌单失败: $e",
          "[LocalMusicListItemsPullDown] Failed to edit music list: $e");
    }
  }
}

Future<void> showDetailsDialog(
    BuildContext context, MusicContainer musicContainer) async {
  await showMusicInfoDialog(context, defaultMusicInfo: musicContainer.info);
}
