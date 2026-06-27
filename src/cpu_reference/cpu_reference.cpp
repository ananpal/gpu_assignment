/******************************************************************************
 *
 *  cpu_reference.cpp
 *
 *  GPU Programming Assignment
 *  Karan Kapoor
 *
 *  Generates the reference dataset for the CUDA SHA-256 kernel.
 *
 ******************************************************************************/

#include <openssl/sha.h>

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

/******************************************************************************
 * Constants
 ******************************************************************************/

constexpr std::size_t DIGEST_SIZE = SHA256_DIGEST_LENGTH;

constexpr int DEFAULT_MIN_LENGTH = 0;
constexpr int DEFAULT_MAX_LENGTH = 64;

constexpr char ALPHABET[] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
"abcdefghijklmnopqrstuvwxyz"
"0123456789";

/******************************************************************************
 * NIST Test Vector
 ******************************************************************************/

struct TestVector
{
    std::string message;

    std::string expectedDigest;
};

/******************************************************************************
 * Temporary Message Object
 ******************************************************************************/

struct Message
{
    std::string text;

    std::array<unsigned char, DIGEST_SIZE> digest;
};

/******************************************************************************
 * Packed Dataset
 *
 * This matches IO_CONTRACT.md exactly.
 ******************************************************************************/

struct Dataset
{
    std::vector<unsigned char> messages;

    std::vector<int32_t> offsets;

    std::vector<int32_t> lengths;

    std::vector<unsigned char> digests;

    int32_t numMessages = 0;
};

/******************************************************************************
 * SHA256 Reference
 ******************************************************************************/

class SHA256Reference
{
public:

    static std::array<unsigned char, DIGEST_SIZE>
    compute(const std::string& message);

    static std::string
    toHex(
        const unsigned char* digest,
        std::size_t length);
};

/******************************************************************************
 * Dataset Generator
 ******************************************************************************/

class DatasetGenerator
{
private:

    std::mt19937 randomEngine;

    std::uniform_int_distribution<int> lengthDistribution;

    std::uniform_int_distribution<int> characterDistribution;

public:

    DatasetGenerator();

    std::string generateRandomMessage();

    Dataset generate(int numberOfMessages);
};

/******************************************************************************
 * Binary Writer
 ******************************************************************************/

class DatasetWriter
{
public:

    static void write(

        const Dataset& dataset,

        const std::string& outputDirectory);
};

/******************************************************************************
 * Validation
 ******************************************************************************/

class Validator
{
public:

    static void verifyNIST();
};

/******************************************************************************
 * SHA256Reference Implementation
 ******************************************************************************/

std::array<unsigned char, DIGEST_SIZE>
SHA256Reference::compute(const std::string& message)
{
    std::array<unsigned char, DIGEST_SIZE> digest{};

    SHA256_CTX context;

    SHA256_Init(&context);

    SHA256_Update(
        &context,
        reinterpret_cast<const unsigned char*>(message.data()),
        message.size());

    SHA256_Final(
        digest.data(),
        &context);

    return digest;
}

std::string
SHA256Reference::toHex(
    const unsigned char* digest,
    std::size_t length)
{
    std::stringstream stream;

    stream << std::hex << std::setfill('0');

    for (std::size_t i = 0; i < length; i++)
    {
        stream
            << std::setw(2)
            << static_cast<int>(digest[i]);
    }

    return stream.str();
}

/******************************************************************************
 * Validator
 ******************************************************************************/

void Validator::verifyNIST()
{
    const std::vector<TestVector> testVectors =
    {
        {
            "",
            "e3b0c44298fc1c149afbf4c8996fb924"
            "27ae41e4649b934ca495991b7852b855"
        },

        {
            "abc",
            "ba7816bf8f01cfea414140de5dae2223"
            "b00361a396177a9cb410ff61f20015ad"
        },

        {
            "abcdbcdecdefdefgefghfghighijhijk"
            "ijkljklmklmnlmnomnopnopq",

            "248d6a61d20638b8e5c026930c3e6039"
            "a33ce45964ff2167f6ecedd419db06c1"
        }
    };

    std::cout
        << "Running NIST SHA-256 validation..."
        << std::endl;

    for (const auto& test : testVectors)
    {
        auto digest =
            SHA256Reference::compute(test.message);

        std::string actual =
            SHA256Reference::toHex(
                digest.data(),
                DIGEST_SIZE);

        if (actual != test.expectedDigest)
        {
            throw std::runtime_error(

                "NIST validation failed for input: " +

                test.message);
        }
    }

    std::cout

        << "All NIST SHA-256 test vectors passed."

        << std::endl;
}
/******************************************************************************
 * DatasetGenerator Implementation
 ******************************************************************************/

DatasetGenerator::DatasetGenerator()

    : randomEngine(std::random_device{}()),
      lengthDistribution(
            DEFAULT_MIN_LENGTH,
            DEFAULT_MAX_LENGTH),
      characterDistribution(
            0,
            static_cast<int>(sizeof(ALPHABET) - 2))
{
}

/******************************************************************************
 * Generate One Random ASCII Message
 ******************************************************************************/

std::string
DatasetGenerator::generateRandomMessage()
{
    int length =
        lengthDistribution(randomEngine);

    std::string message;

    message.reserve(length);

    for (int i = 0; i < length; i++)
    {
        message.push_back(

            ALPHABET[
                characterDistribution(randomEngine)]);
    }

    return message;
}

/******************************************************************************
 * Generate Complete Dataset
 ******************************************************************************/

Dataset
DatasetGenerator::generate(
    int numberOfMessages)
{
    Dataset dataset;

    dataset.numMessages =
        numberOfMessages;

    int32_t currentOffset = 0;

    for (int i = 0;
         i < numberOfMessages;
         i++)
    {
        /*************************************************
         * Generate one message
         *************************************************/

        std::string message =
            generateRandomMessage();

        /*************************************************
         * Compute SHA256
         *************************************************/

        auto digest =
            SHA256Reference::compute(message);

        /*************************************************
         * Save offset
         *************************************************/

        dataset.offsets.push_back(
            currentOffset);

        /*************************************************
         * Save length
         *************************************************/

        dataset.lengths.push_back(

            static_cast<int32_t>(
                message.size()));

        /*************************************************
         * Append message bytes
         *************************************************/

        dataset.messages.insert(

            dataset.messages.end(),

            message.begin(),

            message.end());

        /*************************************************
         * Append digest bytes
         *************************************************/

        dataset.digests.insert(

            dataset.digests.end(),

            digest.begin(),

            digest.end());

        /*************************************************
         * Update offset
         *************************************************/

        currentOffset +=
            static_cast<int32_t>(
                message.size());
    }

    return dataset;
}
/******************************************************************************
 * DatasetWriter Implementation
 ******************************************************************************/

void DatasetWriter::write(
    const Dataset& dataset,
    const std::string& outputDirectory)
{
    fs::create_directories(outputDirectory);

    /**********************************************************************
     * messages.bin
     **********************************************************************/

    std::ofstream messagesFile(
        outputDirectory + "/messages.bin",
        std::ios::binary);

    if (!messagesFile)
    {
        throw std::runtime_error(
            "Unable to create messages.bin");
    }

    if (!dataset.messages.empty())
    {
        messagesFile.write(
            reinterpret_cast<const char*>(dataset.messages.data()),
            dataset.messages.size());
    }

    messagesFile.close();

    /**********************************************************************
     * offsets.bin
     **********************************************************************/

    std::ofstream offsetsFile(
        outputDirectory + "/offsets.bin",
        std::ios::binary);

    if (!offsetsFile)
    {
        throw std::runtime_error(
            "Unable to create offsets.bin");
    }

    offsetsFile.write(
        reinterpret_cast<const char*>(dataset.offsets.data()),
        dataset.offsets.size() * sizeof(int32_t));

    offsetsFile.close();

    /**********************************************************************
     * lengths.bin
     **********************************************************************/

    std::ofstream lengthsFile(
        outputDirectory + "/lengths.bin",
        std::ios::binary);

    if (!lengthsFile)
    {
        throw std::runtime_error(
            "Unable to create lengths.bin");
    }

    lengthsFile.write(
        reinterpret_cast<const char*>(dataset.lengths.data()),
        dataset.lengths.size() * sizeof(int32_t));

    lengthsFile.close();

    /**********************************************************************
     * expected_digests.bin
     **********************************************************************/

    std::ofstream digestFile(
        outputDirectory + "/expected_digests.bin",
        std::ios::binary);

    if (!digestFile)
    {
        throw std::runtime_error(
            "Unable to create expected_digests.bin");
    }

    digestFile.write(
        reinterpret_cast<const char*>(dataset.digests.data()),
        dataset.digests.size());

    digestFile.close();

    /**********************************************************************
     * meta.txt
     **********************************************************************/

    std::ofstream metaFile(
        outputDirectory + "/meta.txt");

    if (!metaFile)
    {
        throw std::runtime_error(
            "Unable to create meta.txt");
    }

    metaFile
        << "num_messages="
        << dataset.numMessages
        << std::endl;

    metaFile.close();

    std::cout << "\nDataset successfully written to "
              << outputDirectory
              << std::endl;

    std::cout << "Messages : "
              << dataset.numMessages
              << std::endl;

    std::cout << "Total Bytes : "
              << dataset.messages.size()
              << std::endl;
}

/******************************************************************************
 * Main
 ******************************************************************************/

int main(int argc, char* argv[])
{
    try
    {
        if (argc < 2)
        {
            std::cout
                << "Usage:\n"
                << argv[0]
                << " <num_messages> [output_directory]\n";

            return EXIT_FAILURE;
        }

        int numberOfMessages =
            std::stoi(argv[1]);

        std::string outputDirectory =
            "data";

        if (argc >= 3)
        {
            outputDirectory =
                argv[2];
        }

        Validator::verifyNIST();

        DatasetGenerator generator;

        Dataset dataset =
            generator.generate(
                numberOfMessages);

        DatasetWriter::write(
            dataset,
            outputDirectory);

        std::cout
            << "\nSUCCESS!\n";

        return EXIT_SUCCESS;
    }
    catch(const std::exception& e)
    {
        std::cerr
            << "\nERROR : "
            << e.what()
            << std::endl;

        return EXIT_FAILURE;
    }
}