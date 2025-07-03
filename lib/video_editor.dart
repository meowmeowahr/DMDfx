import 'dart:typed_data';

import 'package:dmdfx/device.dart';
import 'package:dmdfx/util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class Frame {
  final Uint8List originalBytes;
  bool overrideGlobalThreshold;
  int localThreshold;

  Image get image {
    return Image.memory(
      originalBytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }

  Frame({
    required this.originalBytes,
    this.overrideGlobalThreshold = false,
    this.localThreshold = 128,
  });
}

class VideoEditor extends StatefulWidget {
  final FxDevice device;

  const VideoEditor({super.key, required this.device});

  @override
  State<VideoEditor> createState() => _VideoEditorState();
}

class _VideoEditorState extends State<VideoEditor>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<Frame> frames = [];
  int selectedFrame = 0;

  int globalThreshold = 128;
  late TabController _frameEditorPreviewTabController;

  @override
  void initState() {
    super.initState();
    _frameEditorPreviewTabController = TabController(length: 2, vsync: this);
  }

  @override
  bool get wantKeepAlive => frames.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Frame Editor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Frames'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                    type: FileType.image,
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    for (final file in result.files) {
                      if (file.bytes != null) {
                        // Decode original image
                        final image = img.decodeImage(file.bytes!);
                        if (image != null) {
                          // Perform cubic scaling
                          final resized = img.copyResize(
                            image,
                            width:
                                int.tryParse(
                                  widget.device.resolution.split("x").first,
                                ) ??
                                32,
                            height:
                                int.tryParse(
                                  widget.device.resolution.split("x").last,
                                ) ??
                                32,
                            interpolation: img.Interpolation.cubic,
                          );
                          final resizedBytes = Uint8List.fromList(
                            img.encodePng(resized),
                          );

                          setState(() {
                            frames.add(Frame(originalBytes: resizedBytes));
                          });
                        }
                      }
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Text('Global Threshold:'),
                Expanded(
                  child: Slider(
                    value: globalThreshold.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    label: globalThreshold.round().toString(),
                    onChanged: (double value) {
                      setState(() {
                        globalThreshold = value.round();
                      });
                    },
                  ),
                ),
                Text('${globalThreshold.round()}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Frame browser (vertical)
                    Container(
                      width: 130,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Text(
                              'Frames',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child:
                                frames.isNotEmpty
                                    ? ListView.builder(
                                      itemCount: frames.length,
                                      itemBuilder: (context, idx) {
                                        final currentThreshold =
                                            frames[idx].overrideGlobalThreshold
                                                ? frames[idx].localThreshold
                                                : globalThreshold;

                                        final previewBytes =
                                            applyGrayscaleThreshold(
                                              frames[idx].originalBytes,
                                              currentThreshold,
                                            );

                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              selectedFrame = idx;
                                            });
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                              horizontal: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  selectedFrame == idx
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer
                                                          .withAlpha(51)
                                                      : Colors.transparent,
                                              border: Border.all(
                                                color:
                                                    selectedFrame == idx
                                                        ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                        : Colors.transparent,
                                                width: 2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                4.0,
                                              ),
                                              child: AspectRatio(
                                                aspectRatio:
                                                    (int.tryParse(
                                                          widget
                                                              .device
                                                              .resolution
                                                              .split("x")
                                                              .first,
                                                        ) ??
                                                        32) /
                                                    (int.tryParse(
                                                          widget
                                                              .device
                                                              .resolution
                                                              .split("x")
                                                              .last,
                                                        ) ??
                                                        32),
                                                child: Image.memory(
                                                  previewBytes,
                                                  fit: BoxFit.contain,
                                                  gaplessPlayback: true,
                                                  filterQuality:
                                                      FilterQuality.none,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                    : const Center(
                                      child: Text(
                                        'No frames',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                          ),
                          if (frames.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: FilledButton.icon(
                                icon: const Icon(Icons.delete),
                                label: const Text('Remove'),
                                style: ButtonStyle(
                                  backgroundColor: WidgetStateProperty.all(
                                    Theme.of(context).colorScheme.error,
                                  ),
                                  foregroundColor: WidgetStateProperty.all(
                                    Theme.of(context).colorScheme.onError,
                                  ),
                                  iconColor: WidgetStateProperty.all(
                                    Theme.of(context).colorScheme.onError,
                                  ),
                                ),

                                onPressed: () {
                                  setState(() {
                                    if (frames.isNotEmpty) {
                                      frames.removeAt(selectedFrame);
                                      if (selectedFrame >= frames.length) {
                                        selectedFrame = frames.length - 1;
                                      }
                                      if (selectedFrame < 0) {
                                        selectedFrame = 0;
                                      }
                                    }
                                  });
                                },
                              ),
                            ),
                          if (frames.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy),
                                label: const Text('Duplicate'),
                                onPressed: () {
                                  setState(() {
                                    frames.add(
                                      Frame(
                                        originalBytes:
                                            frames[selectedFrame].originalBytes,
                                        localThreshold:
                                            frames[selectedFrame]
                                                .localThreshold,
                                        overrideGlobalThreshold:
                                            frames[selectedFrame]
                                                .overrideGlobalThreshold,
                                      ),
                                    );
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Main frame preview and timeline
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Frame preview
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, previewConstraints) {
                                final maxWidth = previewConstraints.maxWidth;
                                final maxHeight = previewConstraints.maxHeight;
                                final aspectRatio =
                                    (int.tryParse(
                                          widget.device.resolution
                                              .split("x")
                                              .first,
                                        ) ??
                                        32) /
                                    (int.tryParse(
                                          widget.device.resolution
                                              .split("x")
                                              .last,
                                        ) ??
                                        32);
                                double displayWidth = maxWidth;
                                double displayHeight = maxWidth / aspectRatio;

                                if (displayHeight > maxHeight) {
                                  displayHeight = maxHeight;
                                  displayWidth = maxHeight * aspectRatio;
                                }

                                final currentFrame =
                                    frames.isNotEmpty
                                        ? frames[selectedFrame]
                                        : null;
                                final imageToDisplay =
                                    currentFrame != null
                                        ? applyGrayscaleThreshold(
                                          currentFrame.originalBytes,
                                          currentFrame.overrideGlobalThreshold
                                              ? currentFrame.localThreshold
                                              : globalThreshold,
                                        )
                                        : null;

                                return Center(
                                  child: Container(
                                    width: displayWidth,
                                    height: displayHeight,
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerLowest,
                                      border: Border.all(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        TabBar(
                                          controller:
                                              _frameEditorPreviewTabController,
                                          tabs: const [
                                            Tab(text: 'Current'),
                                            Tab(text: 'Preview'),
                                          ],
                                        ),
                                        Expanded(
                                          child: TabBarView(
                                            controller:
                                                _frameEditorPreviewTabController,
                                            children: [
                                              frames.isNotEmpty
                                                  ? Image.memory(
                                                    frames[selectedFrame]
                                                        .originalBytes,
                                                    fit: BoxFit.contain,
                                                    gaplessPlayback: true,
                                                    filterQuality:
                                                        FilterQuality.none,
                                                  )
                                                  : const Center(
                                                    child: Text(
                                                      'No frames',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ),
                                              imageToDisplay != null
                                                  ? Image.memory(
                                                    imageToDisplay,
                                                    fit: BoxFit.contain,
                                                    gaplessPlayback: true,
                                                    filterQuality:
                                                        FilterQuality.none,
                                                  )
                                                  : const Center(
                                                    child: Text(
                                                      'No frames to preview',
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Individual Frame Threshold Options
                          if (frames.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value:
                                            frames[selectedFrame]
                                                .overrideGlobalThreshold,
                                        onChanged: (bool? value) {
                                          setState(() {
                                            frames[selectedFrame]
                                                    .overrideGlobalThreshold =
                                                value ?? false;
                                          });
                                        },
                                      ),
                                      const Text('Override Global Threshold'),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value:
                                              frames[selectedFrame]
                                                  .localThreshold
                                                  .toDouble(),
                                          min: 0,
                                          max: 255,
                                          divisions: 255,
                                          label:
                                              frames[selectedFrame]
                                                  .localThreshold
                                                  .round()
                                                  .toString(),
                                          onChanged:
                                              frames[selectedFrame]
                                                      .overrideGlobalThreshold
                                                  ? (double value) {
                                                    setState(() {
                                                      frames[selectedFrame]
                                                              .localThreshold =
                                                          value.round();
                                                    });
                                                  }
                                                  : null, // Disable slider if not overriding
                                        ),
                                      ),
                                      if (frames[selectedFrame]
                                          .overrideGlobalThreshold)
                                        Text(
                                          '${frames[selectedFrame].overrideGlobalThreshold ? frames[selectedFrame].localThreshold.round() : globalThreshold.round()}',
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          // Timeline (Card remains the same, assuming it's part of your existing code)
                          Card(
                            // ... (Your existing timeline code goes here)
                            child: Container(
                              height: 50, // Placeholder height for the timeline
                              alignment: Alignment.center,
                              child: const Text('Timeline Placeholder'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
