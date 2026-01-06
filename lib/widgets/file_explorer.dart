import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:term_deck/models/ssh_connection.dart';
import 'package:term_deck/theme/app_theme.dart';

class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });
}

class FileExplorer extends StatefulWidget {
  final SSHConnectionConfig config;
  final String? currentPath;
  final ValueChanged<String>? onPathChange;

  const FileExplorer({
    super.key,
    required this.config,
    this.currentPath,
    this.onPathChange,
  });

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> with AutomaticKeepAliveClientMixin {
  SSHClient? _client;
  SftpClient? _sftp;
  String _currentPath = '';
  List<FileItem> _files = [];
  bool _loading = false;
  String? _error;
  bool _isInitialized = false;
  final Set<String> _selectedFiles = {};
  bool _showHiddenFiles = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Default to user's home directory
    _currentPath = widget.currentPath ?? '/home/${widget.config.username}';
    // Only connect if not already initialized (cache check)
    if (!_isInitialized) {
      _connect();
    }
  }

  @override
  void didUpdateWidget(FileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPath != null && widget.currentPath != _currentPath) {
      _navigateTo(widget.currentPath!);
    }
  }

  Future<void> _connect() async {
    debugPrint('[FileExplorer] Starting SSH connection...');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('[FileExplorer] Connecting to ${widget.config.host}:${widget.config.port}...');

      final socket = await SSHSocket.connect(
        widget.config.host,
        widget.config.port,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[FileExplorer] Connection timeout');
          throw TimeoutException('SSH connection timeout (10s)');
        },
      );

      debugPrint('[FileExplorer] Creating SSH client...');
      _client = SSHClient(
        socket,
        username: widget.config.username,
        onPasswordRequest: () => widget.config.password ?? '',
        identities: widget.config.privateKey != null
            ? [...SSHKeyPair.fromPem(widget.config.privateKey!)]
            : null,
      );

      debugPrint('[FileExplorer] Opening SFTP session...');
      _sftp = await _client!.sftp().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[FileExplorer] SFTP session timeout');
          throw TimeoutException('SFTP session timeout (10s)');
        },
      );

      debugPrint('[FileExplorer] Connected successfully');
      _loadDirectory(_currentPath);
    } catch (e) {
      debugPrint('[FileExplorer] Connection error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'SSH connection failed: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _loadDirectory(String path) async {
    if (_sftp == null) {
      debugPrint('[FileExplorer] Cannot load directory: SFTP not connected');
      return;
    }

    debugPrint('[FileExplorer] Loading directory: $path');
    setState(() {
      _loading = true;
      _error = null;
      _selectedFiles.clear();
    });

    try {
      final realPath = await _sftp!.absolute(path).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[FileExplorer] Path resolution timeout');
          throw TimeoutException('Path resolution timeout (5s)');
        },
      );

      debugPrint('[FileExplorer] Resolved path: $realPath');

      final items = await _sftp!.listdir(realPath).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[FileExplorer] Directory listing timeout');
          throw TimeoutException('Directory listing timeout (10s)');
        },
      );

      debugPrint('[FileExplorer] Found ${items.length} items');

      final files = <FileItem>[];
      for (final item in items) {
        if (item.filename == '.' || item.filename == '..') continue;

        // Skip hidden files if toggle is off
        if (!_showHiddenFiles && item.filename.startsWith('.')) continue;

        files.add(FileItem(
          name: item.filename,
          path: '$realPath/${item.filename}'.replaceAll('//', '/'),
          isDirectory: item.attr.isDirectory,
          size: item.attr.size ?? 0,
          modified: item.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
              : null,
        ));
      }

      // Sort: directories first, then alphabetically
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      debugPrint('[FileExplorer] Displaying ${files.length} files');

      if (!mounted) return;
      setState(() {
        _currentPath = realPath;
        _files = files;
        _loading = false;
        _isInitialized = true; // Mark as initialized after successful load
      });

      widget.onPathChange?.call(realPath);
    } catch (e) {
      debugPrint('[FileExplorer] Error loading directory: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load directory: ${e.toString()}';
        _loading = false;
        // Don't mark as initialized on error, allow retry
      });
    }
  }

  void _navigateTo(String path) {
    _loadDirectory(path);
  }

  void _navigateUp() {
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      final parent = parts.isEmpty ? '/' : parts.join('/');
      _navigateTo(parent);
    }
  }

  Future<void> _deleteSelected() async {
    if (_sftp == null || _selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface0,
        title: Text(
          'Delete ${_selectedFiles.length} item${_selectedFiles.length > 1 ? 's' : ''}?',
          style: const TextStyle(color: AppColors.text),
        ),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(color: AppColors.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final path in _selectedFiles) {
      try {
        final file = _files.firstWhere((f) => f.path == path);
        if (file.isDirectory) {
          await _sftp!.rmdir(path);
        } else {
          await _sftp!.remove(path);
        }
      } catch (e) {
        // Show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }

    _loadDirectory(_currentPath);
  }

  Future<void> _downloadSelected() async {
    if (_sftp == null || _selectedFiles.isEmpty) return;

    try {
      final Directory? downloadDir;
      if (Platform.isAndroid) {
        downloadDir = await getExternalStorageDirectory();
      } else {
        downloadDir = await getDownloadsDirectory();
      }

      if (downloadDir == null) {
        throw Exception('Could not access download directory');
      }

      for (final path in _selectedFiles) {
        final file = _files.firstWhere((f) => f.path == path);
        if (file.isDirectory) continue; // Skip directories

        final localPath = '${downloadDir.path}/${file.name}';
        final remoteFile = await _sftp!.open(path);
        final localFile = File(localPath);

        final sink = localFile.openWrite();
        await for (final chunk in remoteFile.read()) {
          sink.add(chunk);
        }
        await sink.close();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: ${file.name}'),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => OpenFile.open(localPath),
              ),
            ),
          );
        }
      }

      setState(() => _selectedFiles.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_sftp == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.bytes == null) continue;

        final remotePath = '$_currentPath/${file.name}'.replaceAll('//', '/');
        final remoteFile = await _sftp!.open(
          remotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );

        await remoteFile.write(Stream.value(file.bytes!));
        await remoteFile.close();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Uploaded: ${file.name}')),
          );
        }
      }

      _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _createFolder() async {
    if (_sftp == null) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface0,
        title: const Text(
          'Create Folder',
          style: TextStyle(color: AppColors.text),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: AppColors.subtext0),
            filled: true,
            fillColor: AppColors.base,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.surface1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.surface1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true || controller.text.trim().isEmpty) return;

    try {
      final folderName = controller.text.trim();
      final folderPath = '$_currentPath/$folderName'.replaceAll('//', '/');
      await _sftp!.mkdir(folderPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created folder: $folderName')),
        );
      }

      _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  IconData _getFileIcon(FileItem file) {
    if (file.isDirectory) return Icons.folder;

    final ext = file.name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'js' || 'ts' || 'py' || 'java' || 'c' || 'cpp' || 'h' || 'go' || 'rs' => Icons.code,
      'json' || 'yaml' || 'yml' || 'xml' || 'toml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.description,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => Icons.image,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audio_file,
      'mp4' || 'avi' || 'mkv' || 'mov' => Icons.video_file,
      'zip' || 'tar' || 'gz' || 'rar' || '7z' => Icons.archive,
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.article,
      'xls' || 'xlsx' => Icons.table_chart,
      _ => Icons.insert_drive_file,
    };
  }

  Color _getFileIconColor(FileItem file) {
    if (file.isDirectory) return AppColors.blue;

    final ext = file.name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => AppColors.blue,
      'js' || 'ts' => AppColors.yellow,
      'py' => AppColors.green,
      'java' => AppColors.peach,
      'json' || 'yaml' || 'yml' => AppColors.mauve,
      'md' || 'txt' => AppColors.text,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => AppColors.pink,
      _ => AppColors.subtext0,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _sftp?.close();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Path bar
        Container(
          padding: const EdgeInsets.all(8),
          color: AppColors.mantle,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: _navigateUp,
                tooltip: 'Go up',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.blue,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => _loadDirectory(_currentPath),
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.blue,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder, size: 18),
                onPressed: _createFolder,
                tooltip: 'Create folder',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.green,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file, size: 18),
                onPressed: _uploadFile,
                tooltip: 'Upload file',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.peach,
                ),
              ),
              IconButton(
                icon: Icon(
                  _showHiddenFiles ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () {
                  setState(() => _showHiddenFiles = !_showHiddenFiles);
                  _loadDirectory(_currentPath);
                },
                tooltip: _showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
                style: IconButton.styleFrom(
                  foregroundColor: _showHiddenFiles ? AppColors.yellow : AppColors.subtext0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentPath,
                  style: TextStyle(
                    color: AppColors.subtext0,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedFiles.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.download, size: 18),
                  onPressed: _downloadSelected,
                  tooltip: 'Download selected',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.blue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _deleteSelected,
                  tooltip: 'Delete selected',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.surface1),
        // File list
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.blue,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                'Failed to load directory',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: TextStyle(
                  color: AppColors.subtext0,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _connect,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.blue,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, color: AppColors.overlay0, size: 32),
            const SizedBox(height: 8),
            Text(
              'Empty directory',
              style: TextStyle(color: AppColors.subtext0, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFiles.contains(file.path);

        return ListTile(
          dense: true,
          leading: Icon(
            _getFileIcon(file),
            size: 18,
            color: _getFileIconColor(file),
          ),
          title: Text(
            file.name,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: !file.isDirectory
              ? Text(
                  _formatSize(file.size),
                  style: TextStyle(
                    color: AppColors.subtext0,
                    fontSize: 11,
                  ),
                )
              : null,
          trailing: Checkbox(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedFiles.add(file.path);
                } else {
                  _selectedFiles.remove(file.path);
                }
              });
            },
            side: BorderSide(color: AppColors.surface2),
            activeColor: AppColors.blue,
          ),
          selected: isSelected,
          selectedTileColor: AppColors.surface0.withValues(alpha: 0.5),
          onTap: () {
            if (file.isDirectory) {
              _navigateTo(file.path);
            } else {
              setState(() {
                if (isSelected) {
                  _selectedFiles.remove(file.path);
                } else {
                  _selectedFiles.add(file.path);
                }
              });
            }
          },
        );
      },
    );
  }
}
