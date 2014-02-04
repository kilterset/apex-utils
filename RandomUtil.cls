/*
 * Static methods for all [some of] your entropy related needs
 *
 * @author: James
 * @date: Feb 2014
 */
public class RandomUtil {

    /**
     * Get a uniformly distributed random integer n, where {@literal lower <= n < upper}
     * @param  lower the lower bound (inclusive) for random number generation
     * @param  upper the upper bound (exclusive) for random number generation
     * @return       an integer greater than or equal to lower, and less than upper
     */
    public static Integer getRandomInteger (Integer lower, Integer upper)
    {
        return (Integer) (Math.floor(Math.random() * (upper - lower)) + lower);
    }

    /**
     * Shuffle a list of objects in-place using the Modern Knuth/Fisher-Yates 
     * shuffle algorithm.
     * <p>
     * Example Usage:
     * <pre>
     * {@code
     * List<String> myList = new List<String>{ 'a', 'b', 'c', 'd' }
     * RandomUtil.shuffle(myList);
     * }
     * </pre>
     * 
     * @param listToShuffle A list of objects to shuffle
     */
    public static void shuffle(List<Object> listToShuffle){
        for(Integer i = listToShuffle.size() - 1; i >= 1; i--) {
            Integer randPos = getRandomInt(0,i);
            Object swapTemp = listToShuffle[randPos];
            listToShuffle[randPos] = listToShuffle[i];
            listToShuffle[i] = swapTemp;
        }
    }
}