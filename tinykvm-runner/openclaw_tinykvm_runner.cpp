#include <tinykvm/machine.hpp>

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr uint64_t kBytesPerMiB = 1024ULL * 1024ULL;

struct RunnerOptions {
  float timeout_seconds = 15.0f;
  uint64_t max_mem_mib = 1024;
  uint64_t max_cow_mib = 256;
  std::string dynamic_loader_path;
  std::vector<std::string> extra_read_prefixes;
  std::vector<std::string> guest_env = {
      "LC_TYPE=C",
      "LC_ALL=C",
      "USER=root",
      "HOME=/",
  };
  std::string program_path;
  std::vector<std::string> program_args;
};

[[noreturn]] void fail_usage(const std::string& message) {
  std::cerr << message << "\n\n";
  std::cerr << "Usage: openclaw-tinykvm-runner [options] -- <program> [args...]\n";
  std::cerr << "Options:\n";
  std::cerr << "  --timeout-seconds <seconds>  Default: 15\n";
  std::cerr << "  --max-mem-mib <mib>          Default: 1024\n";
  std::cerr << "  --max-cow-mib <mib>          Default: 256\n";
  std::cerr << "  --dynamic-loader <path>      Optional override for dynamic ELF loader\n";
  std::cerr << "  --read-prefix <path>         Extra readable path prefix inside the guest\n";
  std::cerr << "  --env KEY=VALUE              Repeatable\n";
  std::exit(2);
}

[[noreturn]] void fail_runtime(const std::string& message, int code = 1) {
  std::cerr << message << "\n";
  std::exit(code);
}

uint64_t parse_u64(const char* raw, const char* flag_name) {
  char* end = nullptr;
  errno = 0;
  const unsigned long long value = std::strtoull(raw, &end, 10);
  if (errno != 0 || end == raw || *end != '\0') {
    fail_usage(std::string("Invalid numeric value for ") + flag_name + ": " + raw);
  }
  return static_cast<uint64_t>(value);
}

float parse_float(const char* raw, const char* flag_name) {
  char* end = nullptr;
  errno = 0;
  const float value = std::strtof(raw, &end);
  if (errno != 0 || end == raw || *end != '\0') {
    fail_usage(std::string("Invalid numeric value for ") + flag_name + ": " + raw);
  }
  return value;
}

std::vector<uint8_t> load_file(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    fail_runtime("Unable to open file: " + path);
  }

  file.seekg(0, std::ios::end);
  const std::streamsize size = file.tellg();
  file.seekg(0, std::ios::beg);
  if (size < 0) {
    fail_runtime("Unable to read file size: " + path);
  }

  std::vector<uint8_t> buffer(static_cast<size_t>(size));
  if (!file.read(reinterpret_cast<char*>(buffer.data()), size)) {
    fail_runtime("Unable to read file contents: " + path);
  }

  return buffer;
}

std::string canonicalize_existing_path(const std::string& raw_path) {
  std::error_code ec;
  const fs::path absolute = fs::absolute(fs::path(raw_path), ec);
  if (ec) {
    return raw_path;
  }

  const fs::path canonical = fs::weakly_canonical(absolute, ec);
  if (ec) {
    return absolute.lexically_normal().string();
  }

  return canonical.string();
}

std::string normalize_absolute_path(const std::string& raw_path) {
  std::error_code ec;
  const fs::path absolute = fs::absolute(fs::path(raw_path), ec);
  if (ec) {
    return raw_path;
  }
  return absolute.lexically_normal().string();
}

bool starts_with_path(const std::string& value, const std::string& prefix) {
  if (prefix.empty()) {
    return false;
  }
  if (value == prefix) {
    return true;
  }
  if (value.size() <= prefix.size()) {
    return false;
  }
  if (value.compare(0, prefix.size(), prefix) != 0) {
    return false;
  }
  return value[prefix.size()] == '/';
}

std::string find_dynamic_loader() {
  const std::vector<std::string> candidates = {
      "/lib64/ld-linux-x86-64.so.2",
      "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
      "/lib/ld-linux-aarch64.so.1",
      "/lib64/ld-linux-aarch64.so.1",
  };

  for (const auto& candidate : candidates) {
    if (fs::exists(candidate)) {
      return candidate;
    }
  }

  fail_runtime("Dynamic ELF detected but no supported dynamic loader was found.");
}

RunnerOptions parse_args(int argc, char** argv) {
  RunnerOptions options;

  for (int i = 1; i < argc; ++i) {
    const std::string_view arg(argv[i]);

    if (arg == "--") {
      ++i;
      if (i >= argc) {
        fail_usage("Missing program after --.");
      }
      options.program_path = argv[i];
      for (++i; i < argc; ++i) {
        options.program_args.emplace_back(argv[i]);
      }
      break;
    }

    if (arg == "--timeout-seconds") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --timeout-seconds.");
      }
      options.timeout_seconds = parse_float(argv[++i], "--timeout-seconds");
      continue;
    }

    if (arg == "--max-mem-mib") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --max-mem-mib.");
      }
      options.max_mem_mib = parse_u64(argv[++i], "--max-mem-mib");
      continue;
    }

    if (arg == "--max-cow-mib") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --max-cow-mib.");
      }
      options.max_cow_mib = parse_u64(argv[++i], "--max-cow-mib");
      continue;
    }

    if (arg == "--env") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --env.");
      }
      options.guest_env.emplace_back(argv[++i]);
      continue;
    }

    if (arg == "--dynamic-loader") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --dynamic-loader.");
      }
      options.dynamic_loader_path = argv[++i];
      continue;
    }

    if (arg == "--read-prefix") {
      if (i + 1 >= argc) {
        fail_usage("Missing value for --read-prefix.");
      }
      options.extra_read_prefixes.emplace_back(argv[++i]);
      continue;
    }

    fail_usage(std::string("Unknown option: ") + std::string(arg));
  }

  if (options.program_path.empty()) {
    fail_usage("Missing target program.");
  }

  return options;
}

}  // namespace

int main(int argc, char** argv) {
  const RunnerOptions options = parse_args(argc, argv);
  const uint64_t max_mem_bytes = options.max_mem_mib * kBytesPerMiB;
  const uint64_t max_cow_bytes = options.max_cow_mib * kBytesPerMiB;

  if (max_cow_bytes > std::numeric_limits<uint32_t>::max()) {
    fail_runtime("TinyKVM max_cow_mem exceeds the current uint32_t limit.");
  }

  const std::string program_exec_path = normalize_absolute_path(options.program_path);
  const std::string program_path = canonicalize_existing_path(options.program_path);
  const std::string workspace_root = canonicalize_existing_path(fs::current_path().string());
  const std::string program_dir = canonicalize_existing_path(fs::path(program_path).parent_path().string());

  std::vector<uint8_t> binary = load_file(program_path);
  const tinykvm::DynamicElf dynamic_elf = tinykvm::is_dynamic_elf(
      std::string_view(reinterpret_cast<const char*>(binary.data()), binary.size()));

  std::vector<std::string> guest_args;
  std::vector<std::string> readable_prefixes = {
      workspace_root,
      program_dir,
      "/lib",
      "/usr/lib",
      "/etc",
  };
  for (const auto& prefix : options.extra_read_prefixes) {
    readable_prefixes.push_back(canonicalize_existing_path(prefix));
  }

  if (dynamic_elf.is_dynamic) {
    const std::string loader_path = canonicalize_existing_path(
        options.dynamic_loader_path.empty() ? find_dynamic_loader() : options.dynamic_loader_path);
    guest_args.push_back(loader_path);
    guest_args.push_back(program_exec_path);
    binary = load_file(loader_path);
    readable_prefixes.push_back(fs::path(loader_path).parent_path().string());
  } else {
    guest_args.push_back(program_exec_path);
  }

  for (const auto& arg : options.program_args) {
    guest_args.push_back(arg);
  }

  tinykvm::Machine::init();
  tinykvm::Machine::install_unhandled_syscall_handler(
      [](tinykvm::vCPU& cpu, unsigned syscall_number) {
        auto regs = cpu.registers();
        regs.rax = -ENOSYS;
        cpu.set_registers(regs);
        if (syscall_number == 0x10000) {
          cpu.stop();
        }
      });

  const tinykvm::MachineOptions machine_options{
      .max_mem = max_mem_bytes,
      .max_cow_mem = static_cast<uint32_t>(max_cow_bytes),
      .reset_free_work_mem = 0,
      .verbose_loader = false,
      .relocate_fixed_mmap = true,
      .executable_heap = dynamic_elf.is_dynamic,
  };

  tinykvm::Machine machine(binary, machine_options);
  machine.set_printer([](const char* data, size_t size) {
    std::fwrite(data, 1, size, stdout);
    std::fflush(stdout);
  });

  machine.fds().set_open_readable_callback([&](std::string& requested_path) -> bool {
    const std::string canonical = canonicalize_existing_path(requested_path);
    if (canonical == program_path || requested_path == program_exec_path) {
      return true;
    }
    return std::any_of(readable_prefixes.begin(), readable_prefixes.end(),
                       [&](const std::string& prefix) { return starts_with_path(canonical, prefix); });
  });

  try {
    machine.setup_linux(guest_args, options.guest_env);
    machine.run(options.timeout_seconds);
  } catch (const tinykvm::MachineTimeoutException& err) {
    std::cerr << "TinyKVM execution timed out after " << options.timeout_seconds << " seconds: "
              << err.what() << "\n";
    return 124;
  } catch (const tinykvm::MachineException& err) {
    std::cerr << "TinyKVM machine exception: " << err.what() << " data=0x" << std::hex << err.data()
              << std::dec << "\n";
    return 70;
  } catch (const std::exception& err) {
    std::cerr << "TinyKVM runner failed: " << err.what() << "\n";
    return 1;
  }

  return static_cast<int>(machine.return_value() & 0xFF);
}
